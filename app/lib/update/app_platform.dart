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

  /// Override for [Platform.environment] so detection can be unit-tested
  /// on any host. Production uses the real process environment.
  final Map<String, String> Function()? environmentOverride;

  /// Override for child-process probing (`dpkg -s`, `uname -m`). Tests stub
  /// this; production runs the real commands.
  final Future<String?> Function(List<String> cmd)? runCmdOverride;

  const AppPlatformDetector({
    this.abiResolver,
    this.resolvedExecutableOverride,
    this.environmentOverride,
    this.runCmdOverride,
  });

  Map<String, String> get _environment =>
      environmentOverride?.call() ?? Platform.environment;

  Future<String?> _run(List<String> cmd) =>
      runCmdOverride?.call(cmd) ?? _realRun(cmd);

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
        String exe;
        try {
          exe = _executablePath();
        } catch (_) {
          exe = '';
        }
        return windowsInstallationKind(exe, _environment);
      case AppPlatform.linux:
        String exe;
        try {
          exe = _executablePath();
        } catch (_) {
          exe = '';
        }
        return linuxInstallationKind(
          exePath: exe,
          environment: _environment,
          runCmd: runCmdOverride,
        );
      default:
        return InstallationKind.installed;
    }
  }

  String _executablePath() => resolvedExecutableOverride ?? Platform.resolvedExecutable;

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
        return windowsArch(_environment['PROCESSOR_ARCHITECTURE']);
      case AppPlatform.linux:
        return linuxArch(await _run(['uname', '-m']));
      default:
        return null;
    }
  }

  /// Windows install layout from the running executable's path and the
  /// installer-related environment variables. Pure (string-based parent
  /// splitting) so every branch is unit tested on any host.
  static InstallationKind windowsInstallationKind(
    String exePath,
    Map<String, String> environment,
  ) {
    // Installed layouts live under LOCALAPPDATA\Programs (per-user Inno Setup)
    // or Program Files, and carry an Inno Setup uninstaller. Anything else is
    // a portable ZIP extraction.
    if (exePath.isEmpty) return InstallationKind.unknown;
    final parts = exePath.toLowerCase().split(RegExp(r'[\\/]'));
    final dir =
        parts.length > 1 ? parts.sublist(0, parts.length - 1).join(r'\') : '';
    if (dir.isEmpty) return InstallationKind.unknown;
    final installedRoots = [
      environment['LOCALAPPDATA']?.toLowerCase(),
      environment['ProgramFiles']?.toLowerCase(),
      environment['ProgramFiles(x86)']?.toLowerCase(),
    ]
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .map((p) => p.replaceAll('/', '\\'))
        .toList();
    if (installedRoots.any((root) {
      // Strip the \\?\ long-path prefix (UNC paths keep it and are handled by
      // the incoming-backslash check below).
      final norm =
          dir.startsWith(r'\\') ? dir : dir.replaceFirst(RegExp(r'^\\\?\\'), '');
      return norm.startsWith('$root\\');
    })) {
      return InstallationKind.installed;
    }
    // Inno Setup leaves unins*.exe / "Uninstall NexaDrive.exe" beside the exe.
    try {
      final uninstallers = File(exePath)
          .parent
          .listSync(followLinks: false)
          .where((f) => f.path.toLowerCase().contains('unins'))
          .toList();
      if (uninstallers.isNotEmpty) return InstallationKind.installed;
    } catch (_) {}
    return InstallationKind.portable;
  }

  /// Linux install layout from the running executable's path, the environment
  /// (AppImage), and an optional `dpkg` probe. Pure (stubbed in tests).
  static Future<InstallationKind> linuxInstallationKind({
    required String exePath,
    required Map<String, String> environment,
    Future<String?> Function(List<String> cmd)? runCmd,
  }) async {
    final appImage = environment['APPIMAGE'];
    if (appImage != null && appImage.isNotEmpty) {
      return InstallationKind.appimage;
    }
    // A packaged .deb install places the binary under /usr (either as a symlink
    // in /usr/bin or the real file in /usr/lib/nexadrive).
    final looksDeb =
        exePath.startsWith('/usr/lib/nexadrive/') || exePath == '/usr/bin/nexadrive';
    if (looksDeb) {
      final probe = (runCmd ?? _realRun)(['dpkg', '-s', 'nexadrive']);
      final known = await probe;
      return known != null ? InstallationKind.deb : InstallationKind.installed;
    }
    return InstallationKind.source;
  }

  /// Windows CPU → manifest arch key. A missing value means 64-bit Windows
  /// (the universal case); anything unrecognized → null (no update offered).
  static String? windowsArch(String? processorArchitecture) {
    final arch = processorArchitecture?.toLowerCase();
    if (arch == 'amd64' || arch == 'x86_64' || arch == null) {
      return ArchNames.desktopX64;
    }
    if (arch == 'arm64' || arch == 'aarch64') return ArchNames.aarch64;
    return null;
  }

  /// Linux `uname -m` → manifest arch key.
  static String? linuxArch(String? unameMachine) {
    final machine = unameMachine?.trim().toLowerCase();
    if (machine == 'x86_64' || machine == 'amd64') {
      return ArchNames.desktopX64;
    }
    if (machine == 'aarch64' || machine == 'arm64') {
      return ArchNames.aarch64;
    }
    return null;
  }

  static Future<String?> _realRun(List<String> cmd) async {
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
  ///
  /// [explicitLinuxKind] is the user's prior package choice (AppImage vs. .deb)
  /// for installs whose layout could not be auto-detected; it wins over the
  /// default fallback so the artifact always matches the install flow.
  ArtifactInfo? select(
    UpdateManifest manifest,
    AppPlatform platform,
    String arch,
    InstallationKind installation, {
    String? explicitLinuxKind,
  }) {
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
      // Portable / unknown Linux installs: honor the user's explicit pick
      // first, then prefer AppImage, then .deb.
      if (explicitLinuxKind != null && kinds.containsKey(explicitLinuxKind)) {
        return kinds[explicitLinuxKind];
      }
      return kinds['appimage'] ?? kinds['deb'];
    }
    return null;
  }
}