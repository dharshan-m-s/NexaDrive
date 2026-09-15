import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexadrive/update/app_platform.dart';
import 'package:nexadrive/update/update_controller.dart';
import 'package:nexadrive/update/update_downloader.dart';
import 'package:nexadrive/update/update_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _payload = 'NexaDrive controller payload bytes 1234567890';

final _payloadSha = sha256.convert(utf8.encode(_payload)).toString();

String _manifestJson(String version,
        {String? minSupport, String? minServer, String? serverApi}) =>
    jsonEncode({
      'version': version,
      'tag': 'v$version',
      'releaseDate': '2026-09-10T12:00:00Z',
      'prerelease': false,
      'minimumSupportedVersion': minSupport,
      'minimumServerVersion': minServer,
      'serverApiVersion': serverApi,
      'releaseNotes': {
        'What\u2019s new': ['Something shinier'],
      },
      'artifacts': {
        'android': {
          'arm64-v8a': {
            'apk': {
              'url': 'https://github.com/acme/app/NexaDrive-$version.apk',
              'sha256': _payloadSha,
              'size': _payload.length,
            },
          },
        },
        'windows': {
          'x64': {
            'installer': {
              'url': 'https://objects.githubusercontent.com/acme/app/setup.exe',
              'sha256': _payloadSha,
              'size': _payload.length,
            },
          },
        },
        'linux': {
          'x64': {
            'appimage': {
              'url': 'https://objects.githubusercontent.com/acme/app/app.AppImage',
              'sha256': _payloadSha,
              'size': _payload.length,
            },
          },
        },
      },
    });

const _manifestUrl =
    'https://github.com/dharshan-m-s/NexaDrive/releases/latest/download/nexadrive-update-manifest.json';

class _FakeDetector extends AppPlatformDetector {
  _FakeDetector() : super(abiResolver: () async => [ArchNames.androidArm64]);

  @override
  AppPlatform get platform => AppPlatform.android;

  @override
  bool get isSupported => true;

  @override
  Future<String?> resolveArch() async => ArchNames.androidArm64;
}

class _FakeRouter extends UpdateRouter {
  bool androidLaunchAttempted = false;
  bool androidLaunchResult = true;

  @override
  Future<bool> launchAndroidInstaller(String path) async {
    androidLaunchAttempted = true;
    return androidLaunchResult;
  }
}

class _MutableVersion {
  String version;
  _MutableVersion(this.version);
}

Future<UpdatePreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return UpdatePreferences(prefs);
}

Future<UpdateController> _controller({
  required http.Client client,
  required UpdateRouter router,
  _MutableVersion? version,
  UpdatePreferences? preferences,
}) async {
  final updatePrefs = preferences ?? await _prefs();
  final source = UpdateSource(client: client, baseUrl: _manifestUrl);
  final downloader = UpdateDownloader(client: client, source: source);
  final v = version ?? _MutableVersion('1.0.0');
  return UpdateController(
    source: source,
    downloader: downloader,
    detector: _FakeDetector(),
    selector: const ArtifactSelector(),
    preferences: updatePrefs,
    router: router,
    loadCurrentVersion: () async => v.version,
  );
}

MockClient _serve({required String version, String? minSupport, String? minServer}) {
  return MockClient((request) async {
    if (request.url.path.contains('nexadrive-update-manifest.json')) {
      return http.Response.bytes(
          utf8.encode(_manifestJson(version, minSupport: minSupport, minServer: minServer)), 200);
    }
    return http.Response.bytes(utf8.encode(_payload), 200);
  });
}

/// Serves the manifest instantly but dribbles the artifact one byte at a
/// time, so a download can be cancelled mid-stream deterministically.
class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.version, {this.minSupport});

  final String version;
  final String? minSupport;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.contains('nexadrive-update-manifest.json')) {
      final body = utf8.encode(_manifestJson(version, minSupport: minSupport));
      return http.StreamedResponse(
        Stream<List<int>>.value(body),
        200,
        contentLength: body.length,
      );
    }
    final payload = utf8.encode(_payload);
    final controller = StreamController<List<int>>();
    unawaited(Future(() async {
      for (final byte in payload) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        controller.add([byte]);
      }
      await controller.close();
    }));
    return http.StreamedResponse(
      controller.stream,
      200,
      contentLength: payload.length,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    try {
      final dir = Directory.fromUri(Uri.file('/tmp/nexadrive_updates'));
      if (dir.existsSync()) {
        for (final f in dir.listSync(followLinks: false)) {
          f.deleteSync(recursive: true);
        }
      }
    } catch (_) {}
  });

  group('checkForUpdates', () {
    test('finds a newer version -> updateAvailable', () async {
      final ctrl = await _controller(
        client: _serve(version: '1.2.0'),
        router: _FakeRouter(),
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      expect(ctrl.status, UpdateStatus.updateAvailable);
      expect(ctrl.hasUpdate, isTrue);
      expect(ctrl.manifest!.version.toString(), '1.2.0');
      expect(ctrl.selectedArtifact, isNotNull);
      expect(ctrl.installerKind, 'apk');
      expect(ctrl.preferences.latestKnownVersion, '1.2.0');
      expect(ctrl.preferences.lastCheckAt, isNotNull);
      expect(ctrl.currentVersion.toString(), '1.1.0');
    });

    test('same version -> upToDate (no downgrade offer)', () async {
      final ctrl = await _controller(
        client: _serve(version: '1.1.0'),
        router: _FakeRouter(),
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      expect(ctrl.status, UpdateStatus.upToDate);
      expect(ctrl.hasUpdate, isFalse);
    });

    test('older remote version is never offered', () async {
      final ctrl = await _controller(
        client: _serve(version: '1.0.0'),
        router: _FakeRouter(),
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      expect(ctrl.status, UpdateStatus.upToDate);
    });

    test('prerelease newer version still offered with label intact', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(_manifestJson('1.2.0-rc.1'))
            ..['prerelease'] = true;
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      });
      final ctrl = await _controller(
        client: client,
        router: _FakeRouter(),
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      expect(ctrl.status, UpdateStatus.updateAvailable);
      expect(ctrl.manifest!.prerelease, isTrue);
    });

    test('minimumSupportedVersion newer than installed -> mandatory', () async {
      final ctrl = await _controller(
        client: _serve(version: '1.3.0', minSupport: '1.2.0'),
        router: _FakeRouter(),
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      expect(ctrl.status, UpdateStatus.mandatory);
    });

    test('transport failure -> offline with retryable error', () async {
      final ctrl = await _controller(
        client: MockClient((request) async => throw http.ClientException('down')),
        router: _FakeRouter(),
        version: _MutableVersion('1.0.0'),
      );
      await ctrl.checkForUpdates();
      expect(ctrl.status, UpdateStatus.offline);
      expect(ctrl.retryable, isTrue);
      expect(ctrl.errorMessage, isNotNull);
    });

    test('404 -> offline, not retryable (no releases yet)', () async {
      final ctrl = await _controller(
        client: MockClient((request) async => http.Response.bytes(utf8.encode('nope'), 404)),
        router: _FakeRouter(),
        version: _MutableVersion('1.0.0'),
      );
      await ctrl.checkForUpdates();
      expect(ctrl.status, UpdateStatus.offline);
      expect(ctrl.retryable, isFalse);
    });

    test('silent check respects the 24h policy; auto check skips after', () async {
      final ctrl = await _controller(
        client: _serve(version: '1.2.0'),
        router: _FakeRouter(),
        version: _MutableVersion('1.1.0'),
      );
      expect(await ctrl.shouldAutoCheck(), isTrue);
      await ctrl.checkForUpdates();
      expect(ctrl.status, UpdateStatus.updateAvailable);
      // Immediately forced again within the 24h window: no-op.
      await ctrl.checkForUpdates();
      expect(ctrl.status, UpdateStatus.updateAvailable);
    });
  });

  group('download', () {
    test('succeeds and lands in readyToInstall', () async {
      final ctrl = await _controller(
        client: _serve(version: '1.2.0'),
        router: _FakeRouter(),
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      await ctrl.download();
      expect(ctrl.status, UpdateStatus.readyToInstall);
      expect(ctrl.downloadedPath, isNotNull);
      final file = File(ctrl.downloadedPath!);
      expect(file.existsSync(), isTrue);
      expect(await file.readAsBytes(), utf8.encode(_payload));
    });

    test('checksum mismatch -> failed and retryable', () async {
      // Serve a manifest with a wrong digest for the Android payload.
      final client = MockClient((request) async {
        if (request.url.path.contains('nexadrive-update-manifest.json')) {
          final json = jsonDecode(_manifestJson('1.2.0'));
          (json['artifacts'] as Map)['android'] = {
            'arm64-v8a': {
              'apk': {
                'url': 'https://github.com/acme/app/NexaDrive-1.2.0.apk',
                'sha256': 'e' * 64,
                'size': _payload.length,
              },
            },
          };
          return http.Response.bytes(utf8.encode(jsonEncode(json)), 200);
        }
        return http.Response.bytes(utf8.encode(_payload), 200);
      });
      final ctrl = await _controller(
        client: client,
        router: _FakeRouter(),
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      await ctrl.download();
      expect(ctrl.status, UpdateStatus.failed);
      expect(ctrl.retryable, isTrue);
      expect(ctrl.errorMessage, contains('verification'));
    });

    test('download without a manifest fails cleanly', () async {
      final ctrl = await _controller(
        client: _serve(version: '1.0.0'),
        router: _FakeRouter(),
        version: _MutableVersion('1.0.0'),
      );
      await ctrl.download();
      expect(ctrl.status, UpdateStatus.failed);
    });

    test('cancelling a mandatory download keeps it mandatory', () async {
      final client = _StreamingClient('1.3.0', minSupport: '1.2.0');
      final source = UpdateSource(client: client, baseUrl: _manifestUrl);
      final v = _MutableVersion('1.1.0');
      final ctrl = UpdateController(
        source: source,
        downloader: UpdateDownloader(client: client, source: source),
        detector: _FakeDetector(),
        selector: const ArtifactSelector(),
        preferences: await _prefs(),
        router: _FakeRouter(),
        loadCurrentVersion: () async => v.version,
      );
      await ctrl.checkForUpdates();
      expect(ctrl.status, UpdateStatus.mandatory);

      final future = ctrl.download();
      // Wait until bytes are flowing, then cancel mid-stream.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (ctrl.receivedBytes == 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(ctrl.receivedBytes, greaterThan(0));
      ctrl.cancelDownload();
      await future;

      // A cancelled mandatory download must not demote to a normal,
      // optional updateAvailable state.
      expect(ctrl.status, UpdateStatus.mandatory);
      expect(ctrl.hasUpdate, isTrue);
    });
  });

  group('install + reconcile', () {
    test('android install hands off to the system installer', () async {
      final router = _FakeRouter();
      final ctrl = await _controller(
        client: _serve(version: '1.2.0'),
        router: router,
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      await ctrl.download();
      await ctrl.install();
      expect(router.androidLaunchAttempted, isTrue);
      expect(ctrl.status, UpdateStatus.installingHandoff);
      expect(ctrl.infoMessage, isNotNull);
    });

    test('blocked android launch surfaces needsUserAction with recovery', () async {
      final router = _FakeRouter()..androidLaunchResult = false;
      final ctrl = await _controller(
        client: _serve(version: '1.2.0'),
        router: router,
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      await ctrl.download();
      await ctrl.install();
      expect(ctrl.status, UpdateStatus.needsUserAction);
      expect(ctrl.infoMessage, isNotNull);
    });

    test('resume reconciliation confirms a completed install', () async {
      final version = _MutableVersion('1.1.0');
      final router = _FakeRouter();
      final ctrl = await _controller(
        client: _serve(version: '1.2.0'),
        router: router,
        version: version,
      );
      await ctrl.checkForUpdates();
      await ctrl.download();
      await ctrl.install();
      expect(ctrl.status, UpdateStatus.installingHandoff);

      // User backed out without installing: still old version on resume.
      await ctrl.reconcileAfterResume();
      expect(ctrl.status, UpdateStatus.updateAvailable);

      // Now simulate completion.
      version.version = '1.2.0';
      await ctrl.reconcileAfterResume();
      expect(ctrl.status, UpdateStatus.completed);
    });
  });

  group('server compatibility', () {
    test('notes the running server version from status', () async {
      final ctrl = await _controller(
        client: _serve(version: '1.2.0'),
        router: _FakeRouter(),
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      expect(ctrl.serverVersion, isNull);
      ctrl.noteServerVersion('1.1.0', '1.0.0');
      expect(ctrl.serverVersion, '1.1.0');
      expect(ctrl.serverApiVersion, '1.0.0');
    });

    test('flags an outdated server against the manifest minimum', () async {
      final ctrl = await _controller(
        client: _serve(version: '1.2.0', minServer: '1.5.0'),
        router: _FakeRouter(),
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      expect(ctrl.manifest!.minimumServerVersion.toString(), '1.5.0');
      expect(ctrl.serverIncompatibleWithManifest, isFalse);
      ctrl.noteServerVersion('1.4.0', '1.0.0');
      expect(ctrl.serverIncompatibleWithManifest, isTrue);
      ctrl.noteServerVersion('1.5.0', '1.0.0');
      expect(ctrl.serverIncompatibleWithManifest, isFalse);
    });

    test('does not flag incompatibility when the server version is unknown',
        () async {
      final ctrl = await _controller(
        client: _serve(version: '1.2.0', minServer: '1.5.0'),
        router: _FakeRouter(),
        version: _MutableVersion('1.1.0'),
      );
      await ctrl.checkForUpdates();
      expect(ctrl.serverIncompatibleWithManifest, isFalse);
      expect(ctrl.serverVersion, isNull);
    });
  });

  group('check policy', () {
    test('manual floor blocks an immediate second manual check', () async {
      final policy = UpdateCheckPolicy();
      final now = DateTime.now();
      expect(policy.shouldAutoCheck(null, now), isTrue);
      // A check happened 10s ago.
      expect(policy.canManualCheck(now.subtract(const Duration(seconds: 10)), now), isFalse);
      expect(policy.canManualCheck(now.subtract(const Duration(seconds: 30)), now), isTrue);
      expect(
        policy.shouldAutoCheck(now.subtract(const Duration(hours: 10)), now),
        isFalse,
      );
      expect(
        policy.shouldAutoCheck(now.subtract(const Duration(hours: 25)), now),
        isTrue,
      );
    });
  });
}