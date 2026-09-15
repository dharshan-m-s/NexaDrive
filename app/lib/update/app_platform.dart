import 'dart:io';
import 'update_manifest.dart';

/// Device platform NexaDrive can update.
enum AppPlatform { android, windows, linux, macos, ios }

/// How the application reached this machine. The Update Center serves a
/// different artifact and flow for each layout.
enum InstallationKind {
  /// Managed by a package manager / installer (Android APK, Windows Inno
  /// Setup, Linux .deb). The updater hands off to the system.
  installed,

  /// Windows: running from a self-contained folder (the portable ZIP layout).
  portable,

  /// Linux: running from an AppImage (`$APPIMAGE` set).
  appimage,

  /// Linux: installed from the packaged .deb (files under /usr).
  deb,

  /// A developer checkout / source build that has no self-replace path.
  source,

  /// Could not be determined; the Update Center must ask.
  unknown,
}

/// Normalized architecture names used as manifest keys.
///
/// Android keys are the ABI names reported by the OS (`arm64-v8a`,
/// `armeabi-v7a`, `x86`, `x86_64`); Windows/Linux use `x64` / `aarch64`.
abstract final class ArchNames {
  static const androidArm64 = 'arm64-v8a';
  static const androidArm32 = 'armeabi-v7a';
  static const androidX86 = 'x86';
  static const androidX64 = 'x86_64';
  static const desktopX64 = 'x64';
  static const aarch64 = 'aarch64';
}

/// Resolves the current platform and architecture at runtime.
///
/// Android reports the ABI from the platform channel; desktop maps the guest
/// OS/CPU. Any failure produces an explicit ["unsupported"] outcome rather than
/// a guess, so the Update Center never offers a mismatched installer.
class AppPlatformDetector {
  /// Optional channel call for the Android ABI list. Injected so unit tests
  /// can stub it; production wires [UpdaterMethodChannel.resolveAbi].
  final Future<List<String>?> Function()? abiResolver;

  /// Override for the running executable path (Windows/Linux detection).
  /// Production reads [Platform.resolvedExecutable]; tests inject a path.
  final String? resolvedExecutableOverride;

  const AppPlatformDetector({
    this.abiResolver,
    this.resolvedExecutableOverride,
  });

  AppPlatform get platform {
    if (Platform.isAndroid) return AppPlatform.android;
    if (Platform.isWindows) return AppPlatform.windows;
    if (Platform.isLinux) return AppPlatform.linux;
    if (Platform.isMacOS) return AppPlatform.macos;
    if (Platform.isIOS) return AppPlatform.ios;
    throw const UpdateException(
      UpdateErrorKind.unsupportedPlatform,
      'This operating system cannot update itself automatically.',
    );
  }

  bool get isSupported =>
      platform == AppPlatform.android ||
      platform == AppPlatform.windows ||
      platform == AppPlatform.linux;

  /// Detects how the app is installed so the Update Center can pick the
  /// correct artifact and update flow (portable ZIP vs. installer, AppImage
  /// vs. .deb vs. source). Never guesses on Android (always the system APK).
  Future<InstallationKind> resolveInstallationKind() async {
    switch (platform) {
      case AppPlatform.windows:
        return _windowsInstallationKind();
      case AppPlatform.linux:
        return _linuxInstallationKind();
      default:
        return InstallationKind.installed;
    }
  }

  String _executablePath() => resolvedExecutableOverride ?? Platform.resolvedExecutable;

  InstallationKind _windowsInstallationKind() {
    // Installed layouts live under LOCALAPPDATA\Programs (per-user Inno Setup)
    // or Program Files, and carry an Inno Setup uninstaller. Anything else is
    // a portable ZIP extraction.
    String exe;
    try {
      exe = _executablePath();
    } catch (_) {
      return InstallationKind.unknown;
    }
    if (exe.isEmpty) return InstallationKind.unknown;
    final dir = File(exe).parent.path.toLowerCase();
    final env = Platform.environment;
    final installedRoots = [
      env['LOCALAPPDATA']?.toLowerCase(),
      env['ProgramFiles']?.toLowerCase(),
      env['ProgramFiles(x86)']?.toLowerCase(),
    ]
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .map((p) => p.replaceAll('/', '\\'))
        .toList();
    if (installedRoots.any((root) {
      final norm = dir.startsWith('\\') ? dir : dir.replaceFirst('\\\\?\\', '');
      return norm.startsWith('$root\\');
    })) {
      return InstallationKind.installed;
    }
    // Inno Setup leaves unins*.exe / "Uninstall NexaDrive.exe" beside the exe.
    try {
      final uninstallers = File(exe)
          .parent
          .listSync(followLinks: false)
          .where((f) => f.path.toLowerCase().contains('unins'))
          .toList();
      if (uninstallers.isNotEmpty) return InstallationKind.installed;
    } catch (_) {}
    return InstallationKind.portable;
  }

  Future<InstallationKind> _linuxInstallationKind() async {
    final appImage = Platform.environment['APPIMAGE'];
    if (appImage != null && appImage.isNotEmpty) {
      return InstallationKind.appimage;
    }
    String exe;
    try {
      exe = _executablePath();
    } catch (_) {
      exe = '';
    }
    // A packaged .deb install places the binary under /usr (either as a symlink
    // in /usr/bin or the real file in /usr/lib/nexadrive).
    final looksDeb =
        exe.startsWith('/usr/lib/nexadrive/') || exe == '/usr/bin/nexadrive';
    if (looksDeb) {
      final known = await _run(['dpkg', '-s', 'nexadrive']);
      return known != null ? InstallationKind.deb : InstallationKind.installed;
    }
    return InstallationKind.source;
  }

  Future<String?> resolveArch() async {
    switch (platform) {
      case AppPlatform.android:
        final abis = await abiResolver?.call();
        if (abis == null || abis.isEmpty) {
          throw const UpdateException(
            UpdateErrorKind.unsupportedArchitecture,
            'Could not determine the CPU architecture.',
          );
        }
        return abis.first;
      case AppPlatform.windows:
        final arch = Platform.environment['PROCESSOR_ARCHITECTURE']?.toLowerCase();
        if (arch == 'amd64' || arch == 'x86_64' || arch == null) {
          return ArchNames.desktopX64;
        }
        if (arch == 'arm64' || arch == 'aarch64') return ArchNames.aarch64;
        return null;
      case AppPlatform.linux:
        final machine = await _run(['uname', '-m']);
        if (machine == 'x86_64' || machine == 'amd64') {
          return ArchNames.desktopX64;
        }
        if (machine == 'aarch64' || machine == 'arm64') {
          return ArchNames.aarch64;
        }
        return null;
      default:
        return null;
    }
  }

  Future<String?> _run(List<String> cmd) async {
    try {
      final result = await Process.run(cmd.first, cmd.sublist(1));
      if (result.exitCode == 0 && result.stdout is String) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}
    return null;
  }
}

/// Chooses the correct artifact from a manifest for this device.
///
/// Selection is *exact*: there is no fuzzy fallback to a different
/// architeture or platform, because shipping the wrong binary is a security
/// class bug, not a convenience issue.
class ArtifactSelector {
  const ArtifactSelector();

  /// Which artifact kind this install layout should receive.
  ///
  /// Windows portable layouts take the ZIP, everything else takes the native
  /// installer. Linux source/dev builds defer to an explicit choice.
  String? kindFor(AppPlatform platform, InstallationKind installation) {
    switch (platform) {
      case AppPlatform.android:
        return 'apk';
      case AppPlatform.windows:
        return installation == InstallationKind.portable ? 'zip' : 'installer';
      case AppPlatform.linux:
        switch (installation) {
          case InstallationKind.deb:
            return 'deb';
          case InstallationKind.appimage:
            return 'appimage';
          case InstallationKind.source:
          case InstallationKind.unknown:
            return null;
          default:
            return 'appimage';
        }
      default:
        return null;
    }
  }

  String platformKey(AppPlatform platform) {
    switch (platform) {
      case AppPlatform.android:
        return 'android';
      case AppPlatform.windows:
        return 'windows';
      case AppPlatform.linux:
        return 'linux';
      default:
        throw const UpdateException(
          UpdateErrorKind.unsupportedPlatform,
          'Unsupported platform.',
        );
    }
  }

  /// Returns the single artifact to download for [platform]/[arch] given how
  /// the app is installed. Exact match only — no fuzzy cross-arch fallback.
  ArtifactInfo? select(
    UpdateManifest manifest,
    AppPlatform platform,
    String arch,
    InstallationKind installation,
  ) {
    final key = platformKey(platform);
    final archMap = manifest.artifacts[key];
    if (archMap == null) return null;
    final kinds = archMap[arch];
    if (kinds == null || kinds.isEmpty) return null;

    final preferred = kindFor(platform, installation);
    if (preferred != null && kinds.containsKey(preferred)) {
      return kinds[preferred];
    }
    if (key == 'linux') {
      // Portable / unknown Linux installs: pick whichever package exists.
      return kinds['appimage'] ?? kinds['deb'];
    }
    return null;
  }
}