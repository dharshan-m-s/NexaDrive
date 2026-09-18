import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexadrive/update/update_downloader.dart';
import 'package:nexadrive/update/update_manifest.dart';

String _hex(List<int> bytes) => sha256.convert(bytes).toString();

ArtifactInfo _info(String url, List<int> bytes) => ArtifactInfo(
      url,
      _hex(bytes),
      bytes.length,
    );

/// Serves [payload] in two chunks and honours `Range` with a real `206`.
///
/// [ignoresRange] models a server that answers a ranged request with `200` and
/// the whole body, which the downloader must detect and restart from.
class _RangeServer extends http.BaseClient {
  _RangeServer(this.payload, {this.ignoresRange = false});

  final List<int> payload;
  final bool ignoresRange;

  /// Every `Range` header the downloader sent, in order (`null` when absent).
  final List<String?> ranges = [];

  late final int split = payload.length ~/ 2;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final range = request.headers['Range'];
    ranges.add(range);
    if (range != null && !ignoresRange) {
      final start =
          int.parse(range.replaceFirst('bytes=', '').split('-').first);
      final body = payload.sublist(start);
      return http.StreamedResponse(
        Stream<List<int>>.value(body),
        206,
        contentLength: body.length,
      );
    }
    // Two chunks, so a pause request has somewhere to land between them.
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([
        payload.sublist(0, split),
        payload.sublist(split),
      ]),
      200,
      contentLength: payload.length,
    );
  }
}

/// Streams the first [emitThenStop] bytes then stalls forever — the classic
/// half-download hang.
class _StallingDownloadClient extends http.BaseClient {
  _StallingDownloadClient({required this.emitThenStop});

  final int emitThenStop;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final payload = utf8.encode('NexaDrive update payload bytes 1234567890');
    final controller = StreamController<List<int>>();
    controller.add(payload.sublist(0, emitThenStop));
    return http.StreamedResponse(
      controller.stream,
      200,
      contentLength: payload.length,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory cache;
  setUp(() {
    cache = Directory.systemTemp.createTempSync('nexadrive_downloader_test');
  });

  group('UpdateDownloader', () {
    final payload = utf8.encode('NexaDrive update payload bytes 1234567890');

    tearDownAll(() {
      try {
        cache.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('downloads, verifies, and finalizes a clean artifact', () async {
      final downloader = UpdateDownloader(
        client: MockClient((request) async {
          expect(request.url.host, 'github.com');
          return http.Response.bytes(payload, 200);
        }),
        cacheProvider: () => cache,
      );
      final info = _info('https://github.com/acme/app/NexaDrive-1.2.0.apk', payload);

      final received = <(int, int?)>[];
      final result = await downloader.download(
        info,
        artifactFileName: 'NexaDrive-1.2.0.apk',
        installerKind: 'apk',
        onProgress: (r, t) => received.add((r, t)),
      );

      expect(result.sha256Hex, info.sha256Hex);
      expect(result.size, payload.length);
      expect(result.installerKind, 'apk');
      expect(await result.file.readAsBytes(), payload);
      expect(received.last.$1, payload.length);
      expect(received.last.$2, payload.length);
      expect(
        Directory('${cache.path}/NexaDrive-1.2.0.apk').existsSync(),
        isFalse,
      );
      expect(
        File('${cache.path}/NexaDrive-1.2.0.apk').existsSync(),
        isTrue,
      );
    });

    test('rejects a checksum mismatch and cleans up the partial', () async {
      final downloader = UpdateDownloader(
        client: MockClient((request) async => http.Response.bytes(payload, 200)),
        cacheProvider: () => cache,
      );
      final info = ArtifactInfo(
        'https://github.com/acme/app/NexaDrive-1.2.0.apk',
        'f' * 64, // wrong digest
        payload.length,
      );

      await expectLater(
        downloader.download(
          info,
          artifactFileName: 'NexaDrive-1.2.0.apk',
          installerKind: 'apk',
        ),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.checksumMismatch)),
      );
      expect(
        File('${cache.path}/NexaDrive-1.2.0.apk.part').existsSync(),
        isFalse,
      );
    });

    test('rejects a size mismatch before writing', () async {
      final downloader = UpdateDownloader(
        client: MockClient((request) async => http.Response.bytes(payload, 200)),
        cacheProvider: () => cache,
      );
      final info = ArtifactInfo(
        'https://github.com/acme/app/NexaDrive-1.2.0.apk',
        _hex(payload),
        payload.length + 100,
      );
      await expectLater(
        downloader.download(
          info,
          artifactFileName: 'NexaDrive-1.2.0.apk',
          installerKind: 'apk',
        ),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.sizeMismatch)),
      );
    });

    test('cancellation surfaces UpdateErrorKind.cancelled and cleans up', () async {
      final downloader = UpdateDownloader(
        client: MockClient((request) async => http.Response.bytes(payload, 200)),
        cacheProvider: () => cache,
      );
      final info = _info('https://github.com/acme/app/NexaDrive-1.2.0.apk', payload);
      await expectLater(
        downloader.download(
          info,
          artifactFileName: 'NexaDrive-1.2.0.apk',
          installerKind: 'apk',
          isCancelled: () => true,
        ),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.cancelled)),
      );
      expect(
        File('${cache.path}/NexaDrive-1.2.0.apk.part').existsSync(),
        isFalse,
      );
    });

    test('a non-200 response becomes http', () async {
      final downloader = UpdateDownloader(
        client: MockClient((request) async => http.Response('oops', 500)),
        cacheProvider: () => cache,
      );
      final info = _info('https://github.com/acme/app/NexaDrive-1.2.0.apk', payload);
      await expectLater(
        downloader.download(
          info,
          artifactFileName: 'NexaDrive-1.2.0.apk',
          installerKind: 'apk',
        ),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.http)),
      );
    });

    test('a redirect off the release hosts is rejected', () async {
      final downloader = UpdateDownloader(
        client: MockClient(
          (request) async => http.Response('', 302, headers: {
              'location': 'https://evil.example.com/NexaDrive-1.2.0.apk',
            }),
        ),
        cacheProvider: () => cache,
      );
      final info = _info('https://github.com/acme/app/NexaDrive-1.2.0.apk', payload);
      await expectLater(
        downloader.download(
          info,
          artifactFileName: 'NexaDrive-1.2.0.apk',
          installerKind: 'apk',
        ),
        throwsA(isA<UpdateException>().having(
          (e) => e.kind,
          'kind',
          UpdateErrorKind.manifestRejected,
        )),
      );
      // Nothing was written anywhere.
      expect(cache.listSync(followLinks: false), isEmpty);
    });

    test('a redirect that downgrades to http is rejected', () async {
      final downloader = UpdateDownloader(
        client: MockClient(
          (request) async => http.Response('', 302, headers: {
              'location': 'http://github.com/acme/app/NexaDrive-1.2.0.apk',
            }),
        ),
        cacheProvider: () => cache,
      );
      final info = _info('https://github.com/acme/app/NexaDrive-1.2.0.apk', payload);
      await expectLater(
        downloader.download(
          info,
          artifactFileName: 'NexaDrive-1.2.0.apk',
          installerKind: 'apk',
        ),
        throwsA(isA<UpdateException>().having(
          (e) => e.kind,
          'kind',
          UpdateErrorKind.manifestRejected,
        )),
      );
    });

    test('a redirect back onto an allowed GitHub host is followed', () async {
      var hops = 0;
      final downloader = UpdateDownloader(
        client: MockClient((request) async {
          // The first hop bounces to GitHub's real object-storage host, the
          // second serves the bytes. Both are on the release allowlist.
          if (hops++ == 0) {
            return http.Response('', 302, headers: {
              'location':
                  'https://objects.githubusercontent.com/NexaDrive-1.2.0.apk',
            });
          }
          return http.Response.bytes(payload, 200);
        }),
        cacheProvider: () => cache,
      );
      final info = _info('https://github.com/acme/app/NexaDrive-1.2.0.apk', payload);

      final result = await downloader.download(
        info,
        artifactFileName: 'NexaDrive-1.2.0.apk',
        installerKind: 'apk',
      );
      expect(hops, 2);
      expect(result.sha256Hex, info.sha256Hex);
      expect(await result.file.readAsBytes(), payload);
    });

    test('a loop of allowed redirects still reaches the bytes', () async {
      var calls = 0;
      final downloader = UpdateDownloader(
        client: MockClient((request) async {
          calls++;
          if (calls < 3) {
            return http.Response('', 302, headers: {
              'location': 'https://github.com/acme/app/NexaDrive-1.2.0.apk',
            });
          }
          return http.Response.bytes(payload, 200);
        }),
        cacheProvider: () => cache,
      );
      final info = _info('https://github.com/acme/app/NexaDrive-1.2.0.apk', payload);

      final result = await downloader.download(
        info,
        artifactFileName: 'NexaDrive-1.2.0.apk',
        installerKind: 'apk',
      );
      expect(result.size, payload.length);
    });

    test('an unbounded redirect chain is rejected', () async {
      final downloader = UpdateDownloader(
        client: MockClient((request) async => http.Response('', 302, headers: {
              'location': 'https://github.com/acme/app/NexaDrive-1.2.0.apk',
            })),
        cacheProvider: () => cache,
      );
      final info = _info('https://github.com/acme/app/NexaDrive-1.2.0.apk', payload);
      await expectLater(
        downloader.download(
          info,
          artifactFileName: 'NexaDrive-1.2.0.apk',
          installerKind: 'apk',
        ),
        throwsA(isA<UpdateException>().having(
          (e) => e.kind,
          'kind',
          UpdateErrorKind.manifestRejected,
        )),
      );
      expect(cache.listSync(followLinks: false), isEmpty);
    });

    test('a mid-stream stall is aborted by the idle watchdog', () async {
      final downloader = UpdateDownloader(
        client: _StallingDownloadClient(emitThenStop: payload.length ~/ 2),
        cacheProvider: () => cache,
        idleTimeout: const Duration(milliseconds: 300),
      );
      final info = _info('https://github.com/acme/app/NexaDrive-1.2.0.apk', payload);
      await expectLater(
        downloader.download(
          info,
          artifactFileName: 'NexaDrive-1.2.0.apk',
          installerKind: 'apk',
        ),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.network)),
      );
      // Nothing was committed, and the partial is cleaned up.
      expect(cache.listSync(followLinks: false), isEmpty);
    });
  });

  group('UpdateDownloader pause and resume', () {
    final payload =
        utf8.encode('NexaDrive resumable payload ' * 40); // ~1080 bytes
    ArtifactInfo info() => _info(
        'https://github.com/acme/app/NexaDrive-1.2.0.apk', payload);
    const fileName = 'NexaDrive-1.2.0.apk';

    test('pausing keeps the partial and reports a resumable offset', () async {
      final client = _RangeServer(payload);
      final downloader = UpdateDownloader(
        client: client,
        cacheProvider: () => cache,
      );

      var pause = false;
      await expectLater(
        downloader.download(
          info(),
          artifactFileName: fileName,
          installerKind: 'apk',
          // Flip the pause request once the first chunk has been counted, so
          // the second chunk observes it.
          onProgress: (received, _) => pause = received > 0,
          isPaused: () => pause,
        ),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.paused)
            .having((e) => e.offset, 'offset', client.split)),
      );

      // The partial survives a pause (unlike a cancel) and its length is
      // exactly the reported checkpoint.
      final part = File('${cache.path}/$fileName.part');
      expect(part.existsSync(), isTrue);
      expect(part.lengthSync(), client.split);
      // Nothing was committed under the final name.
      expect(File('${cache.path}/$fileName').existsSync(), isFalse);
    });

    test('resuming continues with a Range request and verifies the result',
        () async {
      final client = _RangeServer(payload);
      final downloader = UpdateDownloader(
        client: client,
        cacheProvider: () => cache,
      );

      var pause = false;
      UpdateException? paused;
      try {
        await downloader.download(
          info(),
          artifactFileName: fileName,
          installerKind: 'apk',
          onProgress: (received, _) => pause = received > 0,
          isPaused: () => pause,
        );
      } on UpdateException catch (e) {
        paused = e;
      }
      expect(paused?.kind, UpdateErrorKind.paused);

      final result = await downloader.download(
        info(),
        artifactFileName: fileName,
        installerKind: 'apk',
        resumeFrom: paused!.offset,
      );

      // A real range request, continuing where the pause stopped.
      expect(client.ranges, [null, 'bytes=${client.split}-']);
      // And the reassembled file is byte-identical and checksum-valid.
      expect(result.sha256Hex, info().sha256Hex);
      expect(result.size, payload.length);
      expect(await result.file.readAsBytes(), payload);
      expect(File('${cache.path}/$fileName.part').existsSync(), isFalse);
    });

    test('a server that ignores Range is detected and restarted', () async {
      final client = _RangeServer(payload, ignoresRange: true);
      final downloader = UpdateDownloader(
        client: client,
        cacheProvider: () => cache,
      );

      // Pretend a valid partial is already on disk.
      final part = File('${cache.path}/$fileName.part')
        ..writeAsBytesSync(payload.sublist(0, 100));
      expect(part.lengthSync(), 100);

      final result = await downloader.download(
        info(),
        artifactFileName: fileName,
        installerKind: 'apk',
        resumeFrom: 100,
      );

      // Sent a range, got a 200, and still produced the complete correct file
      // rather than appending a second copy.
      expect(client.ranges, ['bytes=100-']);
      expect(result.size, payload.length);
      expect(await result.file.readAsBytes(), payload);
      expect(result.sha256Hex, info().sha256Hex);
    });

    test('a checkpoint that does not match the partial restarts cleanly',
        () async {
      final client = _RangeServer(payload);
      final downloader = UpdateDownloader(
        client: client,
        cacheProvider: () => cache,
      );

      // Claim 500 bytes are on disk when only 40 are.
      File('${cache.path}/$fileName.part')
          .writeAsBytesSync(payload.sublist(0, 40));

      final result = await downloader.download(
        info(),
        artifactFileName: fileName,
        installerKind: 'apk',
        resumeFrom: 500,
      );

      expect(client.ranges, [null], reason: 'must not trust a bogus offset');
      expect(await result.file.readAsBytes(), payload);
      expect(result.sha256Hex, info().sha256Hex);
    });

    test('a cancelled download still discards its partial', () async {
      final client = _RangeServer(payload);
      final downloader = UpdateDownloader(
        client: client,
        cacheProvider: () => cache,
      );

      await expectLater(
        downloader.download(
          info(),
          artifactFileName: fileName,
          installerKind: 'apk',
          isCancelled: () => true,
        ),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.cancelled)),
      );
      expect(cache.listSync(followLinks: false), isEmpty);
    });
  });

  group('UpdateDownloader.sanitizeFileName', () {
    test('strips directory components (no path traversal)', () {
      expect(
        UpdateDownloader.sanitizeFileName('../../windows/system32/evil.exe'),
        'evil.exe',
      );
      expect(
        UpdateDownloader.sanitizeFileName('..\\..\\evil.apk'),
        'evil.apk',
      );
    });

    test('replaces unsafe characters', () {
      expect(
        UpdateDownloader.sanitizeFileName('NexaDrive 1.2 <upd>.apk'),
        'NexaDrive_1.2__upd_.apk',
      );
      expect(
        UpdateDownloader.sanitizeFileName('x\u0000y/../../z.deb'),
        'z.deb',
      );
    });

    test('falls back for empty or reserved names', () {
      expect(UpdateDownloader.sanitizeFileName(''), 'nexadrive-update.bin');
      expect(UpdateDownloader.sanitizeFileName('.'), 'nexadrive-update.bin');
      expect(UpdateDownloader.sanitizeFileName('..'), 'nexadrive-update.bin');
      expect(UpdateDownloader.sanitizeFileName('/'), 'nexadrive-update.bin');
    });

    test('keeps ordinary artifact names intact', () {
      const name = 'NexaDrive-1.2.0-windows-x64-setup.exe';
      expect(UpdateDownloader.sanitizeFileName(name), name);
    });
  });
}