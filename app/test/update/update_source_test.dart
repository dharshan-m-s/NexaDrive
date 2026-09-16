import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexadrive/update/update_manifest.dart';
import 'package:nexadrive/update/update_source.dart';

final String _manifestBody = '''
{
  "version": "1.2.0",
  "tag": "v1.2.0",
  "releaseDate": "2026-09-10T12:00:00Z",
  "prerelease": false,
  "artifacts": {
    "android": {
      "arm64-v8a": {
        "apk": {"url": "https://github.com/a/b.apk", "sha256": "${'a' * 64}", "size": 10}
      }
    }
  }
}
''';

UpdateSource sourceReturning(http.Client client) => UpdateSource(
      client: client,
      baseUrl:
          'https://github.com/dharshan-m-s/NexaDrive/releases/latest/download/nexadrive-update-manifest.json',
    );

/// A client whose response carries headers but a body stream that never emits
/// nor closes — the exact deadlock that used to leave the Update Center stuck.
class _StalledBodyClient extends http.BaseClient {
  _StalledBodyClient(this.body);

  final Stream<List<int>> Function() body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(body(), 200, contentLength: 1);
  }
}

void main() {
  group('UpdateSource host policy', () {
    test('allows github.com and *.githubusercontent.com only', () {
      expect(UpdateConfig.allowsHost('github.com'), isTrue);
      expect(UpdateConfig.allowsHost('objects.githubusercontent.com'), isTrue);
      expect(UpdateConfig.allowsHost('release-assets.githubusercontent.com'), isTrue);
      expect(UpdateConfig.allowsHost('api.github.com'), isFalse);
      expect(UpdateConfig.allowsHost('evil.example.com'), isFalse);
    });

    test('rejects a non-https source URL', () {
      final source = UpdateSource(
        client: MockClient((_) async => http.Response(_manifestBody, 200)),
        baseUrl: 'http://github.com/dharshan-m-s/NexaDrive/x',
      );
      expect(() => source.fetchLatest(),
          throwsA(isA<UpdateException>()
              .having((e) => e.kind, 'kind', UpdateErrorKind.malformedManifest)));
    });

    test('rejects an off-allowlist source host', () {
      final source = UpdateSource(
        client: MockClient((_) async => http.Response(_manifestBody, 200)),
        baseUrl: 'https://evil.example.com/NexaDrive/manifest.json',
      );
      expect(() => source.fetchLatest(),
          throwsA(isA<UpdateException>()
              .having((e) => e.kind, 'kind', UpdateErrorKind.malformedManifest)));
    });
  });

  group('UpdateSource.fetchLatest', () {
    test('parses a 200 manifest', () async {
      final source = sourceReturning(
        MockClient((request) async {
          expect(request.url.host, 'github.com');
          expect(request.headers['If-None-Match'], isNull);
          return http.Response(_manifestBody, 200, headers: {
            'etag': '"abc"',
            'last-modified': 'Thu, 10 Sep 2026 12:00:00 GMT',
          });
        }),
      );
      final result = await source.fetchLatest();
      expect(result.manifest!.version.toString(), '1.2.0');
      expect(result.etag, '"abc"');
      expect(result.notModified, isFalse);
      await source.close();
    });

    test('returns notModified on 304', () async {
      final source = sourceReturning(
        MockClient((request) async {
          expect(request.headers['If-None-Match'], '"abc"');
          return http.Response('', 304);
        }),
      );
      final result = await source.fetchLatest(etag: '"abc"');
      expect(result.notModified, isTrue);
      expect(result.manifest, isNull);
      await source.close();
    });

    test('maps 404 to notFound', () async {
      final source = sourceReturning(
        MockClient((request) async => http.Response('nope', 404)),
      );
      expect(
        () => source.fetchLatest(),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.notFound)),
      );
      await source.close();
    });

    test('maps a transport failure to network', () async {
      final source = sourceReturning(
        MockClient((request) async => throw http.ClientException('boom')),
      );
      expect(
        () => source.fetchLatest(),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.network)),
      );
      await source.close();
    });

    test('maps unparseable JSON to malformedManifest', () async {
      final source = sourceReturning(
        MockClient((request) async => http.Response('{"version": ', 200)),
      );
      expect(
        () => source.fetchLatest(),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.malformedManifest)),
      );
      await source.close();
    });

    test('follows a redirect that stays on the release hosts', () async {
      var hops = 0;
      final source = sourceReturning(MockClient((request) async {
        hops++;
        if (hops == 1) {
          return http.Response('', 302, headers: {
            'location':
                'https://github.com/dharshan-m-s/NexaDrive/releases/download/v1.2.0/nexadrive-update-manifest.json',
          });
        }
        return http.Response(_manifestBody, 200, headers: {
          'etag': '"abc"',
        });
      }));
      final result = await source.fetchLatest();
      expect(hops, 2);
      expect(result.manifest!.version.toString(), '1.2.0');
      await source.close();
    });

    test('rejects a manifest redirect off the release hosts', () async {
      final source = sourceReturning(MockClient((request) async {
        return http.Response('', 302, headers: {
          'location': 'https://evil.example.com/nexadrive-update-manifest.json',
        });
      }));
      expect(
        () => source.fetchLatest(),
        throwsA(isA<UpdateException>().having(
          (e) => e.kind,
          'kind',
          UpdateErrorKind.manifestRejected,
        )),
      );
      await source.close();
    });

    test('a stalled body still terminates as a timeout', () async {
      // Server sends headers but then never delivers a body. This is the
      // classic infinite-"Preparing…" scenario: without a bound on the body
      // read the check would hang forever.
      final never = StreamController<List<int>>();
      final client = _StalledBodyClient(() => never.stream);
      final source = UpdateSource(
        client: client,
        baseUrl:
            'https://github.com/dharshan-m-s/NexaDrive/releases/latest/download/nexadrive-update-manifest.json',
        timeout: const Duration(milliseconds: 200),
      );
      await expectLater(
        () => source.fetchLatest(),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.network)),
      );
      await source.close();
      await never.close();
    });
  });

  group('UpdateSource.resolveArtifact', () {
    test('accepts allowed hosts', () {
      final source = sourceReturning(MockClient((_) async => http.Response('', 200)));
      final uri = source.resolveArtifact(ArtifactInfo(
        'https://objects.githubusercontent.com/acme/app/NexaDrive-1.2.0.apk',
        'a' * 64,
        123,
      ));
      expect(uri.host, 'objects.githubusercontent.com');
    });

    test('rejects disallowed hosts', () {
      final source = sourceReturning(MockClient((_) async => http.Response('', 200)));
      expect(
        () => source.resolveArtifact(ArtifactInfo(
          'https://files.example.com/app.apk',
          'a' * 64,
          123,
        )),
        throwsA(isA<UpdateException>()
            .having((e) => e.kind, 'kind', UpdateErrorKind.malformedManifest)),
      );
    });
  });

  test('manifest cache JSON round-trips through prefs-backed storage', () async {
    final m = UpdateManifest.fromJsonString(_manifestBody);
    final jsonStr = jsonEncode(m.toJson());
    final back = UpdateManifest.fromJsonString(jsonStr);
    expect(back.version.toString(), '1.2.0');
  });
}