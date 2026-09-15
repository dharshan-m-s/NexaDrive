import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'session.dart';
import 'transfer_queue.dart';

const String nexadriveBackgroundTransferTask = 'nexadrive.backgroundTransfers';

@pragma('vm:entry-point')
void nexadriveBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      final session = Session();
      await session.load();
      if (session.serverUrl == null || session.token == null) return true;
      final queue = TransferQueue(Api(session));
      final pending = (await queue.items()).where((item) => item.status != 'completed').toList();
      if (pending.isEmpty) return true;
      await queue.process();
      return true;
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
    _initialized = true;
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
  }

  static Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    await initialize();
    await Workmanager().cancelByUniqueName(nexadriveBackgroundTransferTask);
  }
}
