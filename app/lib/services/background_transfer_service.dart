import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
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

      // Only one process may drive the queue. If the app is in the foreground
      // it owns the transfers, and the background worker stays out of the
      // way instead of uploading the same file a second time.
      if (await UploadManager.isForegroundOwnerAlive()) return true;

      final manager = UploadManager.background();
      manager.attach(Api(session));
      final pending = await manager.runPending();
      return pending == 0;
    } catch (error, stack) {
      debugPrint('NexaDrive background transfer failed: $error\n$stack');
      return false;
    }
  });
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(NexaDriveUploadTaskHandler());
}

class NexaDriveUploadTaskHandler extends TaskHandler {
  UploadManager? _manager;
  Api? _api;
  Session? _session;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      _session = Session();
      await _session!.load();
      if (_session!.serverUrl == null || _session!.token == null) {
        await FlutterForegroundTask.stopService();
        return;
      }
      if (await UploadManager.isForegroundOwnerAlive()) {
        await FlutterForegroundTask.stopService();
        return;
      }
      _api = Api(_session!);
      _manager = UploadManager.background();
      _manager!.attach(_api!);
      unawaited(_run());
    } catch (e) {
      debugPrint('Foreground task start failed: $e');
    }
  }

  Future<void> _run() async {
    if (_manager == null) return;
    try {
      await _manager!.ready;
      await _manager!.reload();
      await _manager!.runPending();
      // Update notification
      final pending = _manager!.pendingCount;
      if (pending == 0) {
        await FlutterForegroundTask.stopService();
        return;
      }
      await FlutterForegroundTask.updateService(
        notificationTitle: 'NexaDrive Uploads',
        notificationText: '$pending file(s) uploading',
      );
      // Keep running while there is work
      Timer(const Duration(seconds: 5), _run);
    } catch (e) {
      debugPrint('Foreground task run failed: $e');
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _manager = null;
    _api = null;
    _session = null;
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {}
}

class BackgroundTransferService {
  static bool _initialized = false;
  static bool _foregroundInitialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(
      nexadriveBackgroundDispatcher,
    );
    _initialized = true;
  }

  static Future<void> initializeForeground() async {
    if (_foregroundInitialized || !Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'nexadrive_uploads',
        channelName: 'NexaDrive Uploads',
        channelDescription: 'File and folder uploads',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _foregroundInitialized = true;
  }

  static Future<bool> _checkPermissions() async {
    if (!Platform.isAndroid) return true;
    if (await FlutterForegroundTask.isIgnoringBatteryOptimizations == false) {
      await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    }
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (Platform.isAndroid) {
      final androidVersion = Platform.version;
      // For Android 13+ notification permission
    }
    return true;
  }

  static Future<void> startForegroundIfNeeded() async {
    if (!Platform.isAndroid) return;
    await initializeForeground();
    await _checkPermissions();
    final manager = UploadManager.current;
    if (manager.pendingCount == 0 && !manager.isBusy) {
      return;
    }
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }
    await FlutterForegroundTask.startService(
      notificationTitle: 'NexaDrive Uploads',
      notificationText: 'Uploading files...',
      callback: startCallback,
    );
  }

  static Future<void> stopForeground() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> schedule() async {
    if (!Platform.isAndroid) return;
    await initialize();
    await startForegroundIfNeeded();
    await Workmanager().registerPeriodicTask(
      nexadriveBackgroundTransferTask,
      nexadriveBackgroundTransferTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: 'nexadrive-transfers',
    );
  }

  static Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    await initialize();
    await stopForeground();
    await Workmanager().cancelByUniqueName(nexadriveBackgroundTransferTask);
  }
}
