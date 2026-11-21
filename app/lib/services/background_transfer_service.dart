import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'durable_download_manager.dart';
import 'session.dart';
import 'upload_manager.dart';

const String nexadriveBackgroundTransferTask = 'nexadrive.backgroundTransfers';

@pragma('vm:entry-point')
void nexadriveBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      final session = Session();
      await session.load();
      if (session.serverUrl == null || session.token == null) return true;

      if (task == DurableDownloadManager.resumeTaskName) {
        // The download queue has its own work/owner ledger. A live foreground
        // process resumes it itself, so the worker must not duplicate bytes.
        if (await DurableDownloadManager.instance.isForegroundOwnerAlive()) {
          return true;
        }
        final downloads = DurableDownloadManager.background();
        downloads.attach(Api(session));
        // The manager's worker holds an FGS lease for every active download.
        final pending = await downloads.resumePending();
        return pending == 0;
      }

      // Only one process may drive the upload queue. If the app is in the
      // foreground it owns the transfers, and the background worker stays out
      // of the way instead of uploading the same file a second time.
      if (await UploadManager.isForegroundOwnerAlive()) return true;

      final manager = UploadManager.background();
      manager.attach(Api(session));
      // UploadManager reports active workers to the shared work ledger, which
      // raises the same Android foreground notification from this background
      // engine. The plugin channel is registered on every FlutterEngine.
      final pending = await manager.runPending();
      return pending == 0;
    } catch (error, stack) {
      debugPrint('NexaDrive background transfer failed: $error\n$stack');
      return false;
    }
  });
}

class BackgroundTransferService {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(
      nexadriveBackgroundDispatcher,
    );
    // Downloads enqueue this one-off task directly; the callback is registered
    // here so a download started before initialization is still scheduled on
    // the next app start.
    DurableDownloadManager.registerResumeScheduler(scheduleDownloadResume);
    _initialized = true;
  }

  /// Schedules a one-off worker that resumes interrupted `.part` downloads.
  static Future<void> scheduleDownloadResume() async {
    if (!Platform.isAndroid) return;
    await initialize();
    await Workmanager().registerOneOffTask(
      DurableDownloadManager.resumeTaskName,
      DurableDownloadManager.resumeTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      tag: 'nexadrive-downloads',
    );
  }

  static Future<void> schedule() async {
    if (!Platform.isAndroid) return;
    await initialize();
    await Workmanager().registerPeriodicTask(
      nexadriveBackgroundTransferTask,
      nexadriveBackgroundTransferTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: 'nexadrive-transfers',
    );
    // Startup after a process death: re-arm the one-off task while the
    // journal still has unfinished rows.
    if (await DurableDownloadManager.instance.hasPendingOnDisk()) {
      await scheduleDownloadResume();
    }
  }

  static Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    await initialize();
    await Workmanager().cancelByUniqueName(nexadriveBackgroundTransferTask);
    await Workmanager()
        .cancelByUniqueName(DurableDownloadManager.resumeTaskName);
    // A signed-out session must not leave downloads queued for the next user.
    await DurableDownloadManager.instance.discardAll();
  }
}
