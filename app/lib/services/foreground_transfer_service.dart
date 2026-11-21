import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A release handle for one foreground transfer.
///
/// Every producer owns exactly one lease and releases it in `finally`, so a
/// cancelled or failed transfer can never leave the notification stuck on.
class ForegroundTransferLease {
  ForegroundTransferLease(this._release);

  final void Function() _release;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

/// Keeps the Android process alive only while real transfer work is running.
///
/// The native side owns a single foreground service and one ongoing
/// notification. This class is a ref-counted ledger: uploads, downloads and
/// sync all register here, and the platform is stopped only when every ledger
/// is empty. Work-driven (not lifecycle-driven) ownership means rotating the
/// screen or backgrounding the app while a transfer is active does not stop
/// the service, while pause/cancel/release stops it promptly.
class ForegroundTransferService {
  ForegroundTransferService._({
    required bool enabled,
    required MethodChannel channel,
    required this.stopGrace,
  })  : _enabled = enabled,
        _channel = channel;

  /// Test seam with an injected channel and an immediate (or short) idle stop.
  @visibleForTesting
  ForegroundTransferService.testing({
    required MethodChannel channel,
    Duration stopGrace = Duration.zero,
  }) : this._(enabled: true, channel: channel, stopGrace: stopGrace);

  static final ForegroundTransferService instance = ForegroundTransferService._(
    enabled: Platform.isAndroid,
    channel: const MethodChannel('nexadrive/foreground_transfer'),
    stopGrace: const Duration(milliseconds: 600),
  );

  /// A short gap between sequential files does not tear down and restart the
  /// service (batch downloads write one file at a time).
  final Duration stopGrace;

  final bool _enabled;
  final MethodChannel _channel;

  int _queuedUploads = 0;
  int _directUploads = 0;
  int _downloads = 0;
  int _syncs = 0;

  String? _desiredStatus;
  String? _shownStatus;

  /// Set before the first start call and cleared only after a successful stop.
  /// A channel error after a native start must still be cleaned up on idle.
  bool _platformMayBeRunning = false;

  Timer? _stopTimer;
  Timer? _retryTimer;
  Future<void> _operation = Future<void>.value();

  /// Bumped on every ledger change. Each queued platform call carries the
  /// generation it was created for; superseded calls are skipped even when a
  /// previous channel call was slow or failed.
  int _generation = 0;
  int _skippedApplies = 0;

  /// A denial is remembered only until the ledger goes idle, so the next
  /// transfer can ask again (and the user can also grant it in system settings).
  bool _notificationPermissionDenied = false;

  /// Completes after all queued platform calls have been attempted.
  Future<void> get idle => _operation;

  /// How many superseded platform calls were discarded. Exposed for the
  /// generation-race test; the ledger never uses it for behaviour.
  @visibleForTesting
  int get skippedApplies => _skippedApplies;

  /// The active upload queue size, reported by [UploadManager].
  void setQueuedUploads(int count) {
    _queuedUploads = count < 0 ? 0 : count;
    _recompute();
  }

  /// One-shot upload (for example a scanned PDF), outside the durable queue.
  ForegroundTransferLease acquireUpload() {
    _directUploads++;
    _recompute();
    return ForegroundTransferLease(() {
      if (_directUploads > 0) _directUploads--;
      _recompute();
    });
  }

  /// One file download, including sync-driven downloads.
  ForegroundTransferLease acquireDownload() {
    _downloads++;
    _recompute();
    return ForegroundTransferLease(() {
      if (_downloads > 0) _downloads--;
      _recompute();
    });
  }

  /// One complete sync run.
  ForegroundTransferLease acquireSync() {
    _syncs++;
    _recompute();
    return ForegroundTransferLease(() {
      if (_syncs > 0) _syncs--;
      _recompute();
    });
  }

  String? _composeStatus() {
    final uploads = _queuedUploads + _directUploads;
    final parts = <String>[];
    if (uploads > 0) {
      parts.add('Uploading $uploads ${uploads == 1 ? 'file' : 'files'}');
    }
    if (_downloads > 0) {
      parts.add(
        'Downloading $_downloads ${_downloads == 1 ? 'file' : 'files'}',
      );
    }
    if (_syncs > 0) parts.add('Syncing folders');
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  void _recompute() {
    final next = _composeStatus();
    if (next == _desiredStatus) return;
    _desiredStatus = next;
    _generation++;
    final generation = _generation;
    _stopTimer?.cancel();
    _stopTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (next == null && stopGrace > Duration.zero) {
      _stopTimer = Timer(stopGrace, () {
        _stopTimer = null;
        _enqueueApply(generation);
      });
      return;
    }
    _enqueueApply(generation);
  }

  void _enqueueApply([int? generation]) {
    final token = generation ?? _generation;
    _operation =
        _operation.then((_) => _apply(token)).catchError((Object _) {});
  }

  Future<void> _apply(int generation) async {
    if (!_enabled) return;
    // A newer ledger change (or a cancelled idle grace) owns the platform now.
    // Comparing the captured status to the live one cannot detect this race:
    // both reads see the same mutable field after a superseding update.
    if (generation != _generation) {
      _skippedApplies++;
      return;
    }
    final desired = _desiredStatus;
    if (desired == _shownStatus) return;

    try {
      if (desired == null) {
        if (_platformMayBeRunning) {
          await _channel.invokeMethod<void>('stop');
        }
        _platformMayBeRunning = false;
        _notificationPermissionDenied = false;
      } else {
        final Map<String, Object?> arguments = <String, Object?>{
          'text': desired,
        };
        if (!_platformMayBeRunning) {
          // The prompt is best effort: denial, a missing Activity (background
          // worker) or a channel error never stops the transfer. A denial is
          // retried by the next transfer once this ledger has gone idle.
          await _ensureNotificationPermission();
          // Assume the native start may have happened even when the channel
          // throws, so the next idle transition still clears the notification.
          _platformMayBeRunning = true;
          await _channel.invokeMethod<void>('start', arguments);
        } else {
          await _channel.invokeMethod<void>('update', arguments);
        }
      }
      _shownStatus = desired;
    } catch (error) {
      // A notification failure must never fail a user's transfer. Keep the
      // shown state unchanged so the next ledger change retries the call.
      debugPrint('NexaDrive transfer notification unavailable: $error');
      if (desired != null) {
        // A background-start restriction can be lifted when the user returns
        // to the app. Retry while work remains, without a tight loop.
        _retryTimer = Timer(const Duration(seconds: 5), () {
          _retryTimer = null;
          if (_desiredStatus != null) {
            _shownStatus = null;
            _enqueueApply(generation);
          }
        });
      }
    }
  }

  /// Whether Android currently allows the ongoing transfer notification.
  ///
  /// Returns true on other platforms and when the channel is unavailable, so
  /// callers never treat a notification problem as a transfer failure.
  Future<bool> notificationsEnabled() async {
    if (!_enabled) return true;
    try {
      return await _channel.invokeMethod<bool>('notificationsEnabled') ?? true;
    } catch (error) {
      debugPrint('NexaDrive notification status unavailable: $error');
      return true;
    }
  }

  /// Requests POST_NOTIFICATIONS when an Activity is available.
  ///
  /// Returns false for a denial or when there is no Activity (a background
  /// isolate), and is safe to call again on a later transfer.
  Future<bool> requestNotificationPermission() async {
    if (!_enabled) return true;
    try {
      return await _channel
              .invokeMethod<bool>('requestNotificationPermission') ??
          true;
    } catch (error) {
      debugPrint('NexaDrive notification prompt unavailable: $error');
      return true;
    }
  }

  Future<void> _ensureNotificationPermission() async {
    if (_notificationPermissionDenied) return;
    if (await notificationsEnabled()) return;
    _notificationPermissionDenied = !await requestNotificationPermission();
  }
}
