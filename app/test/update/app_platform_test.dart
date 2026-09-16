import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/update/app_platform.dart';
import 'package:nexadrive/update/semver.dart';
import 'package:nexadrive/update/update_manifest.dart';

ArtifactInfo _art(String name) =>
    ArtifactInfo('https://github.com/acme/repo/$name', 'a' * 64, 100);

UpdateManifest _fullManifest() => UpdateManifest(
      version: const SemVersion(1, 2, 0),
      tag: 'v1.2.0',
      releaseDate: DateTime.utc(2026, 9, 10),
      prerelease: false,
      minimumSupportedVersion: null,
      releaseNotes: const ReleaseNotes({}),
      artifacts: {
        'android': {
          for (final abi in const ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'])
            abi: {'apk': _art('NexaDrive-1.2.0.apk')},
        },
        'windows': {
          'x64': {
            'installer': _art('NexaDrive-1.2.0-windows-x64-setup.exe'),
            'zip': _art('NexaDrive-1.2.0-windows-x64.zip'),
          },
        },
        'linux': {
          'x64': {
            'appimage': _art('NexaDrive-1.2.0-linux-x86_64.AppImage'),
            'deb': _art('NexaDrive-1.2.0-linux-amd64.deb'),
          },
        },
      },
    );

void main() {
  group('AppPlatformDetector installation detection (pure)', () {
    test('Windows: per-user Inno Setup layout under LOCALAPPDATA', () {
      expect(
        AppPlatformDetector.windowsInstallationKind(
          r'C:\Users\u\AppData\Local\Programs\NexaDrive\nexadrive.exe',
          {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'},
        ),
        InstallationKind.installed,
      );
    });

    test('Windows: machine-wide layouts under Program Files', () {
      for (final key in const ['ProgramFiles', 'ProgramFiles(x86)']) {
        expect(
          AppPlatformDetector.windowsInstallationKind(
            r'D:\Program Files\NexaDrive\nexadrive.exe',
            {key: r'D:\Program Files'},
          ),
          InstallationKind.installed,
          reason: 'root key $key',
        );
      }
    });

    test('Windows: root match is prefix-bound, not sibling', () {
      expect(
        AppPlatformDetector.windowsInstallationKind(
          r'C:\Users\u\AppData\LocalProgramsX\nexadrive.exe',
          {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'},
        ),
        InstallationKind.portable,
      );
    });

    test('Windows: a folder outside the installer roots is portable', () {
      expect(
        AppPlatformDetector.windowsInstallationKind(
          r'D:\games\NexaDrive\nexadrive.exe',
          {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'},
        ),
        InstallationKind.portable,
      );
    });

    test('Windows: an Inno Setup uninstaller beside the exe means installed',
        () {
      final dir = Directory.systemTemp.createTempSync('nexadrive-unins');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}${Platform.pathSeparator}unins000.exe')
          .writeAsBytesSync([]);
      expect(
        AppPlatformDetector.windowsInstallationKind(
          '${dir.path}${Platform.pathSeparator}nexadrive.exe',
          const {},
        ),
        InstallationKind.installed,
      );
    });

    test('Windows: unknown when no executable path is available', () {
      expect(
        AppPlatformDetector.windowsInstallationKind('', const {}),
        InstallationKind.unknown,
      );
    });

    test('Linux: APPIMAGE env wins over every other layout', () {
      expect(
        AppPlatformDetector.linuxInstallationKind(
          exePath: '/usr/lib/nexadrive/nexadrive',
          environment: const {'APPIMAGE': '/home/u/Downloads/NexaDrive.AppImage'},
          runCmd: (cmd) async => 'Package: nexadrive\n',
        ),
        completion(InstallationKind.appimage),
      );
    });

    test('Linux: /usr/lib/nexadrive plus dpkg -s success is a .deb', () {
      expect(
        AppPlatformDetector.linuxInstallationKind(
          exePath: '/usr/lib/nexadrive/nexadrive',
          environment: const {},
          runCmd: (cmd) async => 'Package: nexadrive\nStatus: install ok installed\n',
        ),
        completion(InstallationKind.deb),
      );
    });

    test('Linux: /usr/bin wrapper with dpkg unavailable falls back to installed',
        () {
      expect(
        AppPlatformDetector.linuxInstallationKind(
          exePath: '/usr/bin/nexadrive',
          environment: const {},
          runCmd: (cmd) async => null,
        ),
        completion(InstallationKind.installed),
      );
    });

    test('Linux: a developer checkout is source (no self-replace path)', () {
      expect(
        AppPlatformDetector.linuxInstallationKind(
          exePath: '/home/dev/nexadrive/build/linux/x64/release/bundle/nexadrive',
          environment: const {},
        ),
        completion(InstallationKind.source),
      );
    });
  });

  group('AppPlatformDetector architecture mapping (pure)', () {
    test('Linux uname -m', () {
      expect(AppPlatformDetector.linuxArch('x86_64'), ArchNames.desktopX64);
      expect(AppPlatformDetector.linuxArch('amd64'), ArchNames.desktopX64);
      expect(AppPlatformDetector.linuxArch('aarch64'), ArchNames.aarch64);
      expect(AppPlatformDetector.linuxArch('arm64'), ArchNames.aarch64);
      expect(AppPlatformDetector.linuxArch('  X86_64  '), ArchNames.desktopX64);
      expect(AppPlatformDetector.linuxArch('armv7l'), isNull);
      expect(AppPlatformDetector.linuxArch(''), isNull);
      expect(AppPlatformDetector.linuxArch(null), isNull);
    });

    test('Windows PROCESSOR_ARCHITECTURE', () {
      expect(AppPlatformDetector.windowsArch('AMD64'), ArchNames.desktopX64);
      expect(AppPlatformDetector.windowsArch('x86_64'), ArchNames.desktopX64);
      expect(AppPlatformDetector.windowsArch(null), ArchNames.desktopX64);
      expect(AppPlatformDetector.windowsArch('ARM64'), ArchNames.aarch64);
      expect(AppPlatformDetector.windowsArch('x86'), isNull);
      expect(AppPlatformDetector.windowsArch('ARM'), isNull);
    });
  });

  group('AppPlatformDetector on this host', () {
    test('the runtime platform is supported', () {
      const detector = AppPlatformDetector();
      expect(detector.platform, isNot(anyOf([null])));
      expect(detector.isSupported, isTrue,
          reason: 'update-capable host (one of android/windows/linux)');
    }, skip: Platform.isAndroid || Platform.isWindows || Platform.isLinux
        ? false
        : 'requires an update-capable host');

    test('Linux override wiring: APPIMAGE env', () {
      final detector = AppPlatformDetector(
        resolvedExecutableOverride: '/usr/lib/nexadrive/nexadrive',
        environmentOverride: () => const {'APPIMAGE': '/x/NexaDrive.AppImage'},
        runCmdOverride: (cmd) async => 'Package: nexadrive\n',
      );
      expect(detector.resolveInstallationKind(),
          completion(InstallationKind.appimage));
    }, skip: !Platform.isLinux ? 'Linux host only' : false);

    test('Linux override wiring: dpkg probe decides deb vs installed', () {
      Future<InstallationKind> resolve(String? dpkgOut) =>
          AppPlatformDetector(
            resolvedExecutableOverride: '/usr/lib/nexadrive/nexadrive',
            environmentOverride: () => const {},
            runCmdOverride: (cmd) async => dpkgOut,
          ).resolveInstallationKind();
      expect(resolve('Package: nexadrive\n'), completion(InstallationKind.deb));
      expect(resolve(null), completion(InstallationKind.installed));
    }, skip: !Platform.isLinux ? 'Linux host only' : false);

    test('Linux override wiring: non-/usr paths are source', () {
      final detector = AppPlatformDetector(
        resolvedExecutableOverride:
            '/home/dev/nexadrive/build/linux/x64/release/bundle/nexadrive',
        environmentOverride: () => const {},
      );
      expect(detector.resolveInstallationKind(),
          completion(InstallationKind.source));
    }, skip: !Platform.isLinux ? 'Linux host only' : false);

    test('Linux arch resolution', () {
      final detector = AppPlatformDetector(
        runCmdOverride: (cmd) async => 'x86_64',
      );
      expect(detector.resolveArch(), completion(ArchNames.desktopX64));
      final arm = AppPlatformDetector(runCmdOverride: (cmd) async => 'aarch64');
      expect(arm.resolveArch(), completion(ArchNames.aarch64));
    }, skip: !Platform.isLinux ? 'Linux host only' : false);
  });

  group('ArtifactSelector', () {
    const selector = ArtifactSelector();

    test('kindFor maps each install layout to its artifact kind', () {
      expect(selector.kindFor(AppPlatform.android, InstallationKind.installed),
          'apk');
      expect(selector.kindFor(AppPlatform.windows, InstallationKind.installed),
          'installer');
      expect(selector.kindFor(AppPlatform.windows, InstallationKind.portable),
          'zip');
      expect(selector.kindFor(AppPlatform.linux, InstallationKind.deb), 'deb');
      expect(selector.kindFor(AppPlatform.linux, InstallationKind.appimage),
          'appimage');
      expect(selector.kindFor(AppPlatform.linux, InstallationKind.installed),
          'appimage');
      expect(selector.kindFor(AppPlatform.linux, InstallationKind.source), isNull);
      expect(selector.kindFor(AppPlatform.linux, InstallationKind.unknown), isNull);
    });

    test('select resolves the right artifact for every platform', () {
      final m = _fullManifest();
      final android = selector.select(
          m, AppPlatform.android, ArchNames.androidArm64, InstallationKind.installed)!;
      expect(android.url.endsWith('.apk'), isTrue);

      final winInstalled = selector.select(m, AppPlatform.windows,
          ArchNames.desktopX64, InstallationKind.installed)!;
      expect(winInstalled.url.contains('-windows-x64-setup.exe'), isTrue);

      final winPortable = selector.select(m, AppPlatform.windows,
          ArchNames.desktopX64, InstallationKind.portable)!;
      expect(winPortable.url.endsWith('-windows-x64.zip'), isTrue);

      final linuxDeb = selector.select(
          m, AppPlatform.linux, ArchNames.desktopX64, InstallationKind.deb)!;
      expect(linuxDeb.url.endsWith('-linux-amd64.deb'), isTrue);

      final linuxAppImage = selector.select(m, AppPlatform.linux,
          ArchNames.desktopX64, InstallationKind.appimage)!;
      expect(linuxAppImage.url.endsWith('.AppImage'), isTrue);
    });

    test('select prefers the explicit Linux choice over the fallback', () {
      final m = _fullManifest();
      final picked = selector.select(
        m,
        AppPlatform.linux,
        ArchNames.desktopX64,
        InstallationKind.source, // undetectable layout, user chose .deb earlier
        explicitLinuxKind: 'deb',
      )!;
      expect(picked.url.endsWith('-linux-amd64.deb'), isTrue);
    });

    test('select defaults an unknown Linux install to AppImage', () {
      final m = _fullManifest();
      final picked = selector.select(m, AppPlatform.linux,
          ArchNames.desktopX64, InstallationKind.unknown)!;
      expect(picked.url.endsWith('.AppImage'), isTrue);
    });

    test('select falls back to the only Linux package published', () {
      final onlyDeb = UpdateManifest(
        version: const SemVersion(1, 2, 0),
        tag: 'v1.2.0',
        releaseDate: DateTime.utc(2026, 9, 10),
        prerelease: false,
        minimumSupportedVersion: null,
        releaseNotes: const ReleaseNotes({}),
        artifacts: {
          'linux': {
            'x64': {'deb': _art('NexaDrive-1.2.0-linux-amd64.deb')},
          },
        },
      );
      final picked = selector.select(onlyDeb, AppPlatform.linux,
          ArchNames.desktopX64, InstallationKind.unknown)!;
      expect(picked.url.endsWith('-linux-amd64.deb'), isTrue);
    });

    test('select never falls back across architectures', () {
      final m = _fullManifest();
      expect(
        selector.select(m, AppPlatform.android, ArchNames.androidX64,
            InstallationKind.installed),
        isNotNull,
        reason: 'universal APK is keyed for every Android ABI',
      );
    });

    test('select returns null when the arch has no published artifact', () {
      final onlyArm64 = UpdateManifest(
        version: const SemVersion(1, 2, 0),
        tag: 'v1.2.0',
        releaseDate: DateTime.utc(2026, 9, 10),
        prerelease: false,
        minimumSupportedVersion: null,
        releaseNotes: const ReleaseNotes({}),
        artifacts: {
          'android': {
            'arm64-v8a': {'apk': _art('NexaDrive-1.2.0.apk')},
          },
          'linux': {
            'x64': {'appimage': _art('NexaDrive-1.2.0-linux-x86_64.AppImage')},
          },
        },
      );
      expect(
        selector.select(onlyArm64, AppPlatform.android, ArchNames.androidArm32,
            InstallationKind.installed),
        isNull,
      );
      expect(
        selector.select(onlyArm64, AppPlatform.linux, ArchNames.aarch64,
            InstallationKind.appimage),
        isNull,
      );
    });

    test('platformKey matches the manifest terminology', () {
      expect(selector.platformKey(AppPlatform.android), 'android');
      expect(selector.platformKey(AppPlatform.windows), 'windows');
      expect(selector.platformKey(AppPlatform.linux), 'linux');
      expect(() => selector.platformKey(AppPlatform.macos),
          throwsA(isA<UpdateException>()));
    });
  });
}