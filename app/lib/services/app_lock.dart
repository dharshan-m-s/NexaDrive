import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Outcome of an App Lock attempt.
enum AppLockResult {
  /// The device verified the user (biometrics or the screen-lock credential).
  unlocked,

  /// The user dismissed the system prompt or cancelled authentication.
  cancelled,

  /// The device has no secure screen lock configured, so App Lock cannot be
  /// honored; the app must not pretend to protect anything.
  noDeviceCredential,

  /// The platform reported an authentication failure.
  failed,
}

/// Platform abstraction for the App Lock feature.
///
/// The contract: ask the *device* to authenticate its user through whatever
/// secure lock it has (fingerprint, face, or the PIN/pattern/password
/// fallback). No NexaDrive password exists anywhere in this feature; the
/// platform layer is the only code that touches Android's authentication
/// APIs.
///
/// The default [AppLockService.platform] talks to the Android host over the
/// `nexadrive/app_lock` method channel. Tests inject a stub through the
/// constructor.
class AppLockService {
  /// The channel-backed platform adapter. Kept as an injectable function so
  /// widget tests can substitute a fake without a platform channel.
  final Future<AppLockResult> Function() authenticateWithDevice;
  final Future<bool> Function() canAuthenticateOnDevice;

  static const _channel = MethodChannel('nexadrive/app_lock');
  static const _enabledKey = 'nexadrive_app_lock_enabled';

  AppLockService({
    Future<AppLockResult> Function()? authenticateWithDevice,
    Future<bool> Function()? canAuthenticateOnDevice,
  })  : authenticateWithDevice = authenticateWithDevice ?? _defaultAuthenticate,
        canAuthenticateOnDevice =
            canAuthenticateOnDevice ?? _defaultCanAuthenticate;

  static Future<AppLockResult> _defaultAuthenticate() async {
    try {
      final unlocked = await _channel.invokeMethod<bool>(
        'authenticate',
        {'reason': 'Unlock NexaDrive'},
      );
      return unlocked == true
          ? AppLockResult.unlocked
          : AppLockResult.cancelled;
    } on PlatformException catch (e) {
      if (e.code == 'no_device_credential') {
        return AppLockResult.noDeviceCredential;
      }
      return AppLockResult.failed;
    } on MissingPluginException {
      return AppLockResult.failed;
    }
  }

  static Future<bool> _defaultCanAuthenticate() async {
    try {
      final ok = await _channel.invokeMethod<bool>('canAuthenticate');
      return ok == true;
    } on Exception {
      return false;
    }
  }

  /// Whether App Lock is switched on. Persisted in plain preferences on
  /// purpose: this is a user *setting*, not a secret. The actual gate is the
  /// device's own credential.
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// Turns App Lock on or off. Enabling is refused when the device has no
  /// secure lock; the caller shows why.
  Future<bool> setEnabled(bool value) async {
    if (value && !await canAuthenticateOnDevice()) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    return true;
  }

  /// Runs one device authentication round.
  Future<AppLockResult> authenticate() => authenticateWithDevice();
}

/// Gate widget: when App Lock is enabled, the child tree is hidden behind an
/// opaque lock screen until the device verifies the user.
///
/// Mounted above the shell, so every screen (files, photos, settings, the
/// Update Center) is covered. Unlock state is held here for the whole app:
/// normal navigation inside the app never re-prompts, and only backgrounding
/// the app arms the lock again.
class AppLockGate extends StatefulWidget {
  final AppLockService service;
  final Widget child;

  const AppLockGate({
    super.key,
    required this.service,
    required this.child,
  });

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  /// Whether the lock screen is currently shown.
  bool _locked = false;

  /// One attempt in flight; the system prompt must never be double-prompted
  /// by lifecycle event storms (app switcher swipes, rotation while hidden).
  bool _authenticating = false;

  /// Set while the app is in the background so a spurious resume (app
  /// switcher preview, notification shade) does not flash the lock screen.
  bool _backgrounded = false;

  /// The setting as of the last check; re-read when the app resumes so a
  /// change made on another surface is honored.
  bool? _enabledKnown;

  /// True after a fail-open: App Lock was on but the device could not
  /// authenticate (no screen lock). A visible, dismissible notice explains
  /// this; a SnackBar would need a Scaffold that the gate cannot assume.
  bool _noCredentialNotice = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _evaluate(initial: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (_backgrounded) {
        _backgrounded = false;
        _evaluate();
      }
    }
  }

  Future<void> _evaluate({bool initial = false}) async {
    final enabled = _enabledKnown ?? await widget.service.isEnabled();
    if (!enabled) {
      _enabledKnown = false;
      if (mounted && _locked) {
        setState(() => _locked = false);
      }
      return;
    }
    _enabledKnown = true;
    if (!_locked && !_authenticating) {
      setState(() {
        _locked = true;
      });
      if (initial) {
        // Lock first (hide content), then prompt.
        await _prompt();
      }
    }
  }

  Future<void> _prompt() async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      final result = await widget.service.authenticate();
      if (!mounted) return;
      if (result == AppLockResult.unlocked) {
        setState(() => _locked = false);
      } else if (result == AppLockResult.noDeviceCredential) {
        // The device lost its screen lock (or never had one). Keeping the
        // gate up would brick the app, so fail open with the reason visible.
        setState(() {
          _locked = false;
          _noCredentialNotice = true;
        });
      }
      // cancelled / failed: remain locked; the user can retry.
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) {
      if (!_noCredentialNotice) return widget.child;
      return Column(
        children: [
          _NoCredentialNotice(onDismiss: () {
            setState(() => _noCredentialNotice = false);
          }),
          Expanded(child: widget.child),
        ],
      );
    }
    return _LockScreen(onRetry: _prompt);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Inline banner shown after a fail-open so the user knows why App Lock did
/// not stop them. Dismissible; disappears once App Lock is turned off.
class _NoCredentialNotice extends StatelessWidget {
  final VoidCallback onDismiss;
  const _NoCredentialNotice({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: ListTile(
          leading: Icon(
            Icons.lock_open_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          title: Text(
            'App Lock is on, but this device has no screen lock.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
          ),
          subtitle: Text(
            'Set a screen lock in Android settings, then turn App Lock on '
            'again — or turn it off here.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: Icon(
              Icons.close_rounded,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// The opaque surface shown while locked. No app content is mounted behind
/// it (the gate returns *instead of* the child), so nothing leaks through.
class _LockScreen extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _LockScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = Theme.of(context).colorScheme.primary;
    return ColoredBox(
      color: brightness == Brightness.dark
          ? const Color(0xFF000000)
          : const Color(0xFFF7F8FA),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 56, color: accent),
            const SizedBox(height: 16),
            Text(
              'NexaDrive is locked',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Unlock with your device screen lock.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.screen_lock_portrait_rounded),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
