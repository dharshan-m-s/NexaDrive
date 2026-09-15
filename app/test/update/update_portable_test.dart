import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nexadrive/update/app_platform.dart';
import 'package:nexadrive/update/update_controller.dart';
import 'package:nexadrive/update/update_downloader.dart';
import 'package:nexadrive/update/update_manifest.dart';
import 'package:nexadrive/update/update_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _baseUrl =
    'https://github.com/dharshan-m-s/NexaDrive/releases/latest/download/nexadrive-update-manifest.json';

class _FakeWindowsPortableDetector extends AppPlatformDetector {
  _FakeWindowsPortableDetector()
      : super(
          abiResolver: () async => null,
          resolvedExecutableOverride: 'C:\\Apps\\NexaDrive\\nexadrive.exe',
        );

  @override
  AppPlatform get platform => AppPlatform.windows;

  @override
  bool get isSupported => true;

  @override
  Future<String?> resolveArch() async => ArchNames.desktopX64;

  @override
  Future<InstallationKind> resolveInstallationKind() async =>
      InstallationKind.portable;
}

class _FakeLinuxDetector extends AppPlatformDetector {
  _FakeLinuxDetector({required this.install})
      : super(resolvedExecutableOverride: '/usr/bin/nexadrive');

  final InstallationKind install;

  @override
  AppPlatform get platform => AppPlatform.linux;

  @override
  bool get isSupported => true;

  @override
  Future<String?> resolveArch() async => ArchNames.desktopX64;

  @override
  Future<InstallationKind> resolveInstallationKind() async => install;
}

class _RouterProbe extends UpdateRouter {
  _RouterProbe(this.executablePath, {this.detachedResult = true});

  final String executablePath;
  final bool detachedResult;
  bool detachedCalled = false;
  String? runDetachedTarget;

  @override
  String? windowsExecutablePath() => executablePath;

  @override
  Future<bool> runDetached(String file) async {
    detachedCalled = true;
    runDetachedTarget = file;
    return detachedResult;
  }
}

class _NeverClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError('network must not be touched in these tests');
  }
}

Future<UpdatePreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return UpdatePreferences(prefs);
}

List<int> _zipBytes({bool withAssetManifest = true}) {
  final archive = Archive();
  archive.addFile(ArchiveFile.string(
    'nexadrive.exe',
    'MZ fake portable executable payload',
  ));
  if (withAssetManifest) {
    archive.addFile(ArchiveFile.string(
      'data/flutter_assets/AssetManifest.bin',
      'fake asset manifest',
    ));
  }
  return ZipEncoder().encode(archive);
}

Future<UpdateController> _portableController(UpdateRouter router) async {
  final source = UpdateSource(client: _NeverClient(), baseUrl: _baseUrl);
  return UpdateController(
    source: source,
    downloader: UpdateDownloader(client: _NeverClient(), source: source),
    detector: _FakeWindowsPortableDetector(),
    selector: const ArtifactSelector(),
    preferences: await _prefs(),
    router: router,
    loadCurrentVersion: () async => '1.1.0',
  );
}

UpdateManifest _linuxManifest(String version) {
  const sha = '0000000000000000000000000000000000000000000000000000000000000000';
  return UpdateManifest.fromJson({
    'version': version,
    'tag': 'v$version',
    'releaseDate': '2026-09-10T12:00:00Z',
    'prerelease': false,
    'minimumSupportedVersion': null,
    'releaseNotes': {'What\u2019s new': ['Update']},
    'artifacts': {
      'linux': {
        'x64': {
          'appimage': {
            'url': 'https://github.com/acme/app/app.AppImage',
            'sha256': sha,
            'size': 12345,
          },
          'deb': {
            'url': 'https://github.com/acme/app/app.deb',
            'sha256': sha,
            'size': 12345,
          },
        },
      },
    },
  });
}

Future<void> _assertController(
  UpdateController ctrl, {
  required UpdateManifest manifest,
}) async {
  ctrl.manifest = manifest;
  ctrl.resolvedPlatform = ctrl.detector.platform;
  ctrl.archLabel = await ctrl.detector.resolveArch();
  ctrl.installationKind = await ctrl.detector.resolveInstallationKind();
  ctrl.selectedArtifact = ctrl.selector.select(
    manifest,
    ctrl.resolvedPlatform!,
    ctrl.archLabel!,
    ctrl.installationKind!,
  );
  ctrl.installerKind = ctrl.selector.kindFor(
        ctrl.resolvedPlatform!,
        ctrl.installationKind!,
      ) ??
      _defaultKindForLinux(manifest, ctrl.archLabel!, null);
}

String? _defaultKindForLinux(UpdateManifest m, String arch, String? explicit) {
  final kinds = m.artifacts['linux']?[arch];
  if (kinds == null || kinds.isEmpty) return null;
  if (explicit != null && kinds.containsKey(explicit)) return explicit;
  if (kinds.containsKey('appimage')) return 'appimage';
  return kinds.keys.first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDir;

  setUp(() {
    appDir = Directory.systemTemp.createTempSync('nexadrive_portable_');
  });

  tearDown(() {
    try {
      if (appDir.existsSync()) appDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Windows portable install', () {
    test('unpacks and hands off to the detached swap helper', () async {
      final exe = File('${appDir.path}${Platform.pathSeparator}nexadrive.exe');
      exe.writeAsStringSync('old running build');
      final zip = File('${appDir.path}${Platform.pathSeparator}update.zip');
      zip.writeAsBytesSync(_zipBytes());

      final router = _RouterProbe(exe.path);
      final ctrl = await _portableController(router);
      ctrl.resolvedPlatform = AppPlatform.windows;
      ctrl.installationKind = InstallationKind.portable;
      ctrl.downloadedPath = zip.path;

      await ctrl.install();

      expect(router.detachedCalled, isTrue);
      expect(
        router.runDetachedTarget,
        endsWith('nexadrive-finish-update.cmd'),
      );
      expect(ctrl.status, UpdateStatus.installingHandoff);
      expect(ctrl.infoMessage, contains('restart NexaDrive'));
      expect(
        File('${appDir.path}${Platform.pathSeparator}nexadrive-finish-update.cmd')
            .existsSync(),
        isTrue,
      );
    });

    test('rejects a payload that is not a NexaDrive build', () async {
      final exe = File('${appDir.path}${Platform.pathSeparator}nexadrive.exe');
      exe.writeAsStringSync('old running build');
      final zip = File('${appDir.path}${Platform.pathSeparator}update.zip');
      zip.writeAsBytesSync(_zipBytes(withAssetManifest: false));

      final ctrl = await _portableController(_RouterProbe(exe.path));
      ctrl.resolvedPlatform = AppPlatform.windows;
      ctrl.installationKind = InstallationKind.portable;
      ctrl.downloadedPath = zip.path;

      await ctrl.install();

      expect(ctrl.status, UpdateStatus.failed);
      expect(ctrl.errorMessage, contains('not look like a valid NexaDrive'));
    });

    test('falls back to restart-to-finish when helper cannot start', () async {
      final exe = File('${appDir.path}${Platform.pathSeparator}nexadrive.exe');
      exe.writeAsStringSync('old running build');
      final zip = File('${appDir.path}${Platform.pathSeparator}update.zip');
      zip.writeAsBytesSync(_zipBytes());

      final ctrl = await _portableController(_RouterProbe(exe.path, detachedResult: false));
      ctrl.resolvedPlatform = AppPlatform.windows;
      ctrl.installationKind = InstallationKind.portable;
      ctrl.downloadedPath = zip.path;

      await ctrl.install();

      expect(ctrl.status, UpdateStatus.readyToInstall);
      expect(ctrl.infoMessage, contains('restart NexaDrive to finish'));
    });
  });

  group('ArtifactSelector', () {
    const selector = ArtifactSelector();

    test('picks zip for a Windows portable layout', () {
      final manifest = UpdateManifest.fromJson({
        'version': '2.0.0',
        'tag': 'v2.0.0',
        'releaseDate': '2026-09-10T12:00:00Z',
        'prerelease': false,
        'releaseNotes': {'Section': ['Note']},
        'artifacts': {
          'windows': {
            'x64': {
              'zip': {
                'url': 'https://github.com/acme/app/nexadrive.zip',
                'sha256': 'a' * 64,
                'size': 1000,
              },
              'installer': {
                'url': 'https://github.com/acme/app/nexadrive.exe',
                'sha256': 'b' * 64,
                'size': 1000,
              },
            },
          },
        },
      });
      expect(
        selector.kindFor(AppPlatform.windows, InstallationKind.portable),
        'zip',
      );
      expect(
        selector.kindFor(AppPlatform.windows, InstallationKind.installed),
        'installer',
      );
      final selected = selector.select(
        manifest,
        AppPlatform.windows,
        ArchNames.desktopX64,
        InstallationKind.portable,
      );
      expect(selected, isNotNull);
      expect(selected!.url, contains('.zip'));
    });

    test('picks deb for a Linux deb installation', () {
      final manifest = _linuxManifest('1.3.0');
      final selected = selector.select(
        manifest,
        AppPlatform.linux,
        ArchNames.desktopX64,
        InstallationKind.deb,
      );
      expect(selected, isNotNull);
      expect(selected!.url, contains('.deb'));
      expect(
        selector.kindFor(AppPlatform.linux, InstallationKind.deb),
        'deb',
      );
    });

    test('unknown Linux installation defaults to whichever package exists', () {
      final manifest = _linuxManifest('1.3.0');
      final selected = selector.select(
        manifest,
        AppPlatform.linux,
        ArchNames.desktopX64,
        InstallationKind.unknown,
      );
      expect(selected, isNotNull);
      expect(selected!.url, contains('.AppImage'));
    });
  });

  group('Linux source build', () {
    test('source installation is unsupported with a development-build message',
        () async {
      final detector = _FakeLinuxDetector(install: InstallationKind.source);
      final manifest = _linuxManifest('1.3.0');
      final source = UpdateSource(client: _NeverClient(), baseUrl: _baseUrl);
      final ctrl = UpdateController(
        source: source,
        downloader: UpdateDownloader(client: _NeverClient(), source: source),
        detector: detector,
        selector: const ArtifactSelector(),
        preferences: await _prefs(),
        router: const UpdateRouter(),
        loadCurrentVersion: () async => '1.1.0',
      );
      await _assertController(ctrl, manifest: manifest);
      await ctrl.checkForUpdates();
      expect(ctrl.status, UpdateStatus.unsupported);
      expect(ctrl.errorMessage, contains('development/source build'));
    });

    test('chooseLinuxPackage reselects the artifact and notifies', () async {
      final detector = _FakeLinuxDetector(install: InstallationKind.unknown);
      final source = UpdateSource(client: _NeverClient(), baseUrl: _baseUrl);
      final ctrl = UpdateController(
        source: source,
        downloader: UpdateDownloader(client: _NeverClient(), source: source),
        detector: detector,
        selector: const ArtifactSelector(),
        preferences: await _prefs(),
        router: const UpdateRouter(),
        loadCurrentVersion: () async => '1.1.0',
      );
      await _assertController(ctrl, manifest: _linuxManifest('1.3.0'));

      var notified = false;
      ctrl.addListener(() => notified = true);

      await ctrl.chooseLinuxPackage('deb');
      expect(ctrl.installerKind, 'deb');
      expect(ctrl.selectedArtifact!.url, contains('.deb'));
      expect(notified, isTrue);
    });
  });
}
