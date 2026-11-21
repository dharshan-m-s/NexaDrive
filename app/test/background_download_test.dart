import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/download_service.dart';
import 'package:nexadrive/services/durable_download_manager.dart';
import 'package:nexadrive/services/foreground_transfer_service.dart';
import 'package:nexadrive/services/session.dart';

class _StreamClient extends http.BaseClient {
  _StreamClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File journal;
  late List<MethodCall> calls;
  late MethodChannel channel;
  late ForegroundTransferService transfers;
  var scheduled = 0;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nexa-download-test');
    journal = File('${dir.path}/queue.jsonl');
    calls = <MethodCall>[];
    scheduled = 0;
    channel = const MethodChannel(
      'nexadrive/foreground_transfer_download_test',
      StandardMethodCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return null;
    });
    transfers = ForegroundTransferService.testing(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Api apiFor(_StreamClient client) {
    final session = Session()
      ..serverUrl = 'http://example.test'
      ..token = 'secret-token';
    return Api(session, client: client);
  }

  int count(String method) =>
      calls.where((MethodCall call) => call.method == method).length;

  test('cancel releases the FGS lease and removes the partial file', () async {
    final client = _StreamClient((request) async {
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable(<List<int>>[
          Uint8List.fromList(const <int>[1, 2, 3]),
          Uint8List.fromList(const <int>[4, 5, 6]),
        ]),
        200,
        headers: <String, String>{'content-length': '6'},
      );
    });
    final api = apiFor(client);
    final manager = DurableDownloadManager.forTesting(
      journal: journal,
      api: api,
      transfers: transfers,
      scheduleResume: () async {
        scheduled++;
      },
    );
    final target = '${dir.path}/cancel.bin';
    final cancel = CancelToken();
    final id = await manager.enqueue(
      remotePath: 'docs/cancel.bin',
      targetPath: target,
      cancel: cancel,
      onProgress: (received, total) {
        if (received >= 3) cancel.cancel();
      },
    );

    await expectLater(manager.waitFor(id), throwsA(isA<SaveCancelled>()));
    // The waiter is completed before the worker's finally releases its lease.
    for (var i = 0; i < 50 && count('stop') == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await transfers.idle;

    expect(scheduled, 1);
    expect(count('start'), 1);
    expect(count('stop'), 1);
    expect(File(target).existsSync(), isFalse);
    expect(
      dir
          .listSync()
          .where((FileSystemEntity entity) => entity.path.endsWith('.part')),
      isEmpty,
    );
    // The journal holds paths and offsets, never the session token.
    expect(journal.readAsStringSync(), isNot(contains('secret-token')));
  });

  test('interrupted download resumes from .part via the one-off worker',
      () async {
    final target = '${dir.path}/resume.bin';
    final now = DateTime.now().toIso8601String();
    final item = DurableDownloadItem(
      id: 'resume-1',
      remotePath: 'docs/resume.bin',
      targetPath: target,
      received: 3,
      total: 6,
      state: DurableDownloadState.downloading,
      createdAt: DateTime.parse(now),
      updatedAt: DateTime.parse(now),
    );
    await journal.writeAsString(
      '${jsonEncode(<String, Object?>{
            'id': item.id,
            'item': item.encode()
          })}\n',
    );
    await File(
      '${dir.path}/.resume.bin.nexadrive-resume-1.part',
    ).writeAsBytes(const <int>[1, 2, 3]);

    final ranges = <String?>[];
    final client = _StreamClient((request) async {
      ranges.add(request.headers['Range']);
      return http.StreamedResponse(
        Stream<List<int>>.value(Uint8List.fromList(const <int>[4, 5, 6])),
        206,
        headers: <String, String>{
          'content-range': 'bytes 3-5/6',
          'content-length': '3',
        },
      );
    });
    final manager = DurableDownloadManager.forTesting(
      journal: journal,
      api: apiFor(client),
      transfers: transfers,
      scheduleResume: () async {
        scheduled++;
      },
    );

    final pending = await manager.resumePending();
    expect(pending, 0);
    expect(ranges, <String?>['bytes=3-']);
    expect(File(target).readAsBytesSync(), <int>[1, 2, 3, 4, 5, 6]);
    for (var i = 0; i < 50 && count('stop') == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await transfers.idle;
    expect(count('start'), 1);
    expect(count('stop'), 1);
  });
}
