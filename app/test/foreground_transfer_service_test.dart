import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nexadrive/services/foreground_transfer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late ForegroundTransferService service;
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    channel = const MethodChannel(
      'nexadrive/foreground_transfer_test',
      StandardMethodCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return null;
    });
    service = ForegroundTransferService.testing(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  String status() {
    final call = calls.lastWhere(
      (MethodCall call) => call.method == 'start' || call.method == 'update',
    );
    return (call.arguments! as Map)['text'] as String;
  }

  int count(String method) =>
      calls.where((MethodCall call) => call.method == method).length;

  test('starts once and tracks concurrent downloads until idle', () async {
    final first = service.acquireDownload();
    await service.idle;
    expect(count('start'), 1);
    expect(status(), 'Downloading 1 file');

    final second = service.acquireDownload();
    await service.idle;
    expect(count('start'), 1);
    expect(count('update'), 1);
    expect(status(), 'Downloading 2 files');

    first.release();
    await service.idle;
    expect(count('stop'), 0);
    expect(status(), 'Downloading 1 file');

    second.release();
    await service.idle;
    expect(count('stop'), 1);
  });

  test('rapid cancel and resume does not duplicate or strand the service',
      () async {
    final first = service.acquireDownload();
    await service.idle;
    first.release();
    final second = service.acquireDownload();
    await service.idle;
    final third = service.acquireDownload();
    await service.idle;

    expect(count('start'), 1);
    expect(count('stop'), 0);
    expect(status(), 'Downloading 2 files');

    second.release();
    third.release();
    await service.idle;
    expect(count('stop'), 1);
  });

  test('uploads and sync share one notification and stop only when all end',
      () async {
    service.setQueuedUploads(3);
    final sync = service.acquireSync();
    await service.idle;
    expect(count('start'), 1);
    expect(status(), 'Uploading 3 files · Syncing folders');

    service.setQueuedUploads(0);
    await service.idle;
    expect(count('stop'), 0);
    expect(status(), 'Syncing folders');

    sync.release();
    await service.idle;
    expect(count('stop'), 1);
  });

  test('superseded applies are skipped during a slow platform call', () async {
    final gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      if (call.method == 'start') await gate.future;
      return null;
    });

    final download = service.acquireDownload();
    // Let the first apply reach the channel before superseding it.
    await Future<void>.delayed(Duration.zero);
    service.setQueuedUploads(2);
    service.setQueuedUploads(0);
    gate.complete();

    await service.idle;
    expect(service.skippedApplies, greaterThan(0));
    expect(count('start'), 1);
    expect(count('stop'), 0);
    expect(status(), 'Downloading 1 file');

    download.release();
    await service.idle;
    expect(count('stop'), 1);
  });

  test('a superseded idle stop cannot stop a newly started transfer', () async {
    final gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      if (call.method == 'start') await gate.future;
      return null;
    });

    final first = service.acquireDownload();
    await Future<void>.delayed(Duration.zero);
    first.release(); // queues a stop behind the blocked start
    final second = service.acquireDownload();
    gate.complete();

    await service.idle;
    expect(service.skippedApplies, greaterThan(0));
    expect(count('stop'), 0);
    expect(status(), 'Downloading 1 file');

    second.release();
    await service.idle;
    expect(count('stop'), 1);
  });
}
