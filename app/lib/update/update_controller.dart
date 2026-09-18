import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'android_updater_channel.dart';
import 'app_platform.dart';
import 'semver.dart';
import 'update_downloader.dart';
import 'update_manifest.dart';
import 'update_source.dart';

/// Lifecycle states of the Update Center.
enum UpdateStatus {
  /// No information yet (fresh install, nothing clicked).
  idle,

  /// A check is in flight (either manual or the once-per-day background check).
  checking,

  /// The installed version is current.
  upToDate,

  /// A newer version exists; normal update.
  updateAvailable,

  /// A newer version exists and the release is mandatory
  /// (`minimumSupportedVersion` exceeds the installed version).
  mandatory,

  /// Downloading with live progress.
  downloading,

  /// The user suspended the download. The partial file is retained, so
  /// [UpdateController.resume] continues from where it stopped instead of
  /// starting over.
  paused,

  /// Size + SHA-256 acceptance pass (post-download).
  verifying,

  /// The verified artifact is on disk and can be installed.
  readyToInstall,

  /// The installer was handed off to the OS/user (system installer, .exe, or
  /// package manager); final confirmation happens on app resume.
  installingHandoff,

  /// Confirmed installed (version bumped or AppImage swapped).
  completed,

  /// The operation failed; [errorMessage] explains why.
  failed,

  /// The attempt was cancelled by the user.
  cancelled,

  /// No network / timeout; a cached manifest may still be shown.
  offline,

  /// Platform or architecture has no supported update path.
  unsupported,

  /// Android refused to start the installer (typically the "install unknown
  /// apps" consent for this source is not granted). The user must grant it in
  /// system settings, then retry; [UpdateController.requestInstallPermission]
  /// opens the exact settings screen.
  needsUserAction,
}

/// Durable state for the Update Center, all in SharedPreferences.
class UpdatePreferences {
  static const _lastCheck = 'nexadrive_update_last_check';
  static const _latestKnown = 'nexadrive_update_latest_version';
  static const _manifestJson = 'nexadrive_update_manifest_json';
  static const _manifestEtag = 'nexadrive_update_manifest_etag';
  static const _manifestLastModified = 'nexadrive_update_manifest_last_modified';

  final SharedPreferences _prefs;
  UpdatePreferences(this._prefs);

  DateTime? get lastCheckAt {
    final raw = _prefs.getString(_lastCheck);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  set lastCheckAt(DateTime? value) {
    if (value == null) {
      _prefs.remove(_lastCheck);
    } else {
      _prefs.setString(_lastCheck, value.toUtc().toIso8601String());
    }
  }

  String? get latestKnownVersion => _prefs.getString(_latestKnown);

  set latestKnownVersion(String? value) {
    if (value == null) {
      _prefs.remove(_latestKnown);
    } else {
      _prefs.setString(_latestKnown, value);
    }
  }

  String? get manifestJson => _prefs.getString(_manifestJson);

  set manifestJson(String? value) {
    if (value == null) {
      _prefs.remove(_manifestJson);
    } else {
      _prefs.setString(_manifestJson, value);
    }
  }

  String? get etag => _prefs.getString(_manifestEtag);

  set etag(String? value) {
    if (value == null) {
      _prefs.remove(_manifestEtag);
    } else {
      _prefs.setString(_manifestEtag, value);
    }
  }

  String? get lastModified => _prefs.getString(_manifestLastModified);

  set lastModified(String? value) {
    if (value == null) {
      _prefs.remove(_manifestLastModified);
    } else {
      _prefs.setString(_manifestLastModified, value);
    }
  }

  UpdateManifest? cachedManifest() {
    final json = manifestJson;
    if (json == null) return null;
    try {
      return UpdateManifest.fromJsonString(json);
    } catch (_) {
      return null;
    }
  }

  void saveManifest(UpdateManifest manifest) {
    manifestJson = jsonEncode(manifest.toJson());
  }
}

/// When the client is allowed to phone home for a new manifest.
class UpdateCheckPolicy {
  /// Once per day for the silent background check.
  static const autoInterval = Duration(hours: 24);

  /// Manual checks are always allowed, but a 15s floor prevents a user from
  /// hammering the endpoint by tapping "Check again".
  static const manualMinGap = Duration(seconds: 15);

  bool shouldAutoCheck(DateTime? lastCheck, DateTime now) =>
      lastCheck == null || now.difference(lastCheck) >= autoInterval;

  bool canManualCheck(DateTime? lastCheck, DateTime now) =>
      lastCheck == null || now.difference(lastCheck) >= manualMinGap;
}

/// OS-specific actions the Update Center takes. Defaults target the real
/// devices; tests subclass and stub every method.
class UpdateRouter {
  const UpdateRouter();

  Future<bool> launchAndroidInstaller(String path) =>
      UpdaterMethodChannel().installApk(path);

  Future<bool> launchWindowsInstaller(String path) async {
    try {
      final process = await Process.start(
        path,
        const <String>[],
        mode: ProcessStartMode.detached,
      );
      stdout.addStream(process.stdout).ignore();
      stderr.addStream(process.stderr).ignore();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openWithSystemInstaller(String path) async {
    try {
      final result = await Process.run('xdg-open', [path]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// For a Linux AppImage run, returns the real AppImage file path.
  String? appImagePath() => Platform.environment['APPIMAGE'];

  /// Path of the *running* Windows executable, or null off Windows or when it
  /// cannot be read. Used to decide the portable layout and as the swap target.
  String? windowsExecutablePath() {
    try {
      final path = Platform.resolvedExecutable;
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  /// Launches [file] (a checked-in helper batch/script) detached so it survives
  /// this process exiting. Returns false if it could not be started.
  Future<bool> runDetached(String file) async {
    try {
      final process = await Process.start(
        file,
        const <String>[],
        mode: ProcessStartMode.detached,
      );
      stdout.addStream(process.stdout).ignore();
      stderr.addStream(process.stderr).ignore();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's "Install unknown apps" screen for this app.
  Future<bool> openInstallPermissionSettings() async {
    try {
      await UpdaterMethodChannel().openUnknownSourceSettings();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether the directory of [path] permits writes (AppImage self-replace
  /// requires the AppImage file to sit in a writable folder).
  bool dirWritable(String? path) {
    if (path == null) return false;
    final file = File(path);
    final dir = file.parent;
    if (!dir.existsSync()) return false;
    final probe = File('${dir.path}/.nexadrive_writable_probe');
    try {
      probe.writeAsStringSync('.');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Drives the whole update lifecycle and notifies listeners on every change.
class UpdateController extends ChangeNotifier {
  final UpdateSource source;
  final UpdateDownloader downloader;
  final AppPlatformDetector detector;
  final ArtifactSelector selector;
  final UpdatePreferences preferences;
  final UpdateCheckPolicy policy;
  final UpdateRouter router;
  final Future<String> Function() loadCurrentVersion;

  UpdateStatus status = UpdateStatus.idle;
  double progress = 0;
  int receivedBytes = 0;
  int? totalBytes;
  UpdateManifest? manifest;
  ArtifactInfo? selectedArtifact;
  String? installerKind;
  String? downloadedPath;
  String? errorMessage;
  String? infoMessage;
  String? archLabel;
  bool retryable = false;
  SemVersion? currentVersion;
  AppPlatform? resolvedPlatform;
  InstallationKind? installationKind;

  /// User's explicit Linux package choice ('appimage' | 'deb') when the install
  /// type could not be auto-detected. Null means "pick AppImage if present".
  String? linuxPackageChoice;

  /// Server release/API version reported by `/api/server/status`. Used to warm
  /// the user when the running server is too old for this client release.
  String? serverVersion;
  String? serverApiVersion;

  bool _busy = false;
  bool _cancelRequested = false;
  bool _handoffPending = false;

  /// Set by [pause]; observed by the downloader between chunks.
  bool _pauseRequested = false;

  /// Byte offset a paused download should continue from. Reset to zero whenever
  /// the download reaches a terminal state or restarts from scratch.
  int _resumeOffset = 0;

  UpdateController({
    required this.source,
    required this.downloader,
    required this.detector,
    required this.selector,
    required this.preferences,
    required this.router,
    UpdateCheckPolicy? policy,
    Future<String> Function()? loadCurrentVersion,
  })  : policy = policy ?? UpdateCheckPolicy(),
        loadCurrentVersion = loadCurrentVersion ?? _loadVersionFromPackages;

  static Future<String> _loadVersionFromPackages() async {
    try {
      final info = await PackageInfo.fromPlatform()
          .timeout(const Duration(seconds: 5));
      return info.version;
    } catch (_) {
      return '0.0.0';
    }
  }

  bool get busy => _busy;

  bool get hasUpdate =>
      status == UpdateStatus.updateAvailable || status == UpdateStatus.mandatory;

  bool get isBackgroundEligible =>
      status == UpdateStatus.idle || status == UpdateStatus.upToDate;

  String? get manifestVersionLabel => manifest?.version.toString();

  String? get latestKnownLabel => preferences.latestKnownVersion;

  DateTime? get lastCheck => preferences.lastCheckAt;

  String get lastCheckLabel {
    final when = preferences.lastCheckAt;
    if (when == null) return 'never';
    final local = when.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  @override
  void dispose() {
    source.close().ignore();
    super.dispose();
  }

  // ------------------------------------------------------------- checking

  /// Whether a silent (non-manual) check may run now under [policy].
  Future<bool> shouldAutoCheck() async =>
      policy.shouldAutoCheck(preferences.lastCheckAt, DateTime.now());

  /// Fetches the release manifest and computes the update decision.
  ///
  /// [manual] true forces a check regardless of the passive 24h cadence
  /// (subject only to the anti-hammer floor); false only runs when the policy
  /// allows it, so the caller can invoke it unconditionally on startup.
  Future<void> checkForUpdates({bool manual = false}) async {
    if (_busy) return;
    if (!manual) {
      if (!await shouldAutoCheck()) return;
    } else if (!policy.canManualCheck(preferences.lastCheckAt, DateTime.now())) {
      return;
    }

    _busy = true;
    retryable = false;
    errorMessage = null;
    progress = 0;
    _cancelRequested = false;
    status = UpdateStatus.checking;
    notifyListeners();

    try {
      if (!detector.isSupported) {
        status = UpdateStatus.unsupported;
        errorMessage =
            'Updates are supported on Android, Windows, and Linux.';
        return;
      }
      resolvedPlatform = detector.platform;
      archLabel = await detector.resolveArch();
      if (archLabel == null) {
        status = UpdateStatus.unsupported;
        errorMessage =
            'No installer is published for this system architecture.';
        return;
      }
      installationKind = await detector.resolveInstallationKind();

      // A Linux build that lives neither as an AppImage nor a packaged .deb
      // is a developer checkout; there is no self-replace path.
      if (resolvedPlatform == AppPlatform.linux &&
          installationKind == InstallationKind.source) {
        status = UpdateStatus.unsupported;
        errorMessage =
            'You are running a development/source build. Updates are not '
            'supported for this setup; run the packaged release instead.';
        return;
      }

      final fetched = await source.fetchLatest(
        etag: preferences.etag,
        lastModified: preferences.lastModified,
      );

      final UpdateManifest resolvedManifest;
      if (fetched.notModified) {
        // 304 from GitHub: fall back to our cached manifest so the display
        // stays correct without a re-download of the JSON.
        final cached = preferences.cachedManifest();
        if (cached == null) {
          throw const UpdateException(
            UpdateErrorKind.malformedManifest,
            'The update cache is empty.',
          );
        }
        resolvedManifest = cached;
      } else {
        final fresh = fetched.manifest;
        if (fresh == null) {
          throw const UpdateException(
            UpdateErrorKind.malformedManifest,
            'The reply did not contain a manifest.',
          );
        }
        resolvedManifest = fresh;
        preferences.saveManifest(resolvedManifest);
        preferences.etag = fetched.etag;
        preferences.lastModified = fetched.lastModified;
      }

      manifest = resolvedManifest;
      preferences.lastCheckAt = DateTime.now();
      preferences.latestKnownVersion = resolvedManifest.version.toString();

      currentVersion = SemVersion.tryParse(await loadCurrentVersion()) ??
          const SemVersion(0, 0, 0);

      final cmp = resolvedManifest.version.compareTo(currentVersion!);
      if (cmp <= 0) {
        status = UpdateStatus.upToDate;
        return;
      }

      status = _isMandatory(resolvedManifest)
          ? UpdateStatus.mandatory
          : UpdateStatus.updateAvailable;

      selectedArtifact = selector.select(
        resolvedManifest,
        resolvedPlatform!,
        archLabel!,
        installationKind ?? InstallationKind.installed,
        explicitLinuxKind: linuxPackageChoice,
      );
      installerKind = selector.kindFor(
            resolvedPlatform!,
            installationKind ?? InstallationKind.installed,
          ) ??
          _defaultArtifactKindFor(
            resolvedManifest,
            resolvedPlatform!,
            archLabel!,
            linuxPackageChoice,
          );
      downloadedPath = null;
    } on UpdateException catch (e) {
      _applyError(e);
    } catch (_) {
      status = UpdateStatus.failed;
      errorMessage = 'Something went wrong while checking for updates.';
      retryable = true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _applyError(UpdateException e) {
    errorMessage = e.message;
    progress = 0;
    final outcome = switch (e.kind) {
      UpdateErrorKind.network => (UpdateStatus.offline, true),
      UpdateErrorKind.notFound => (UpdateStatus.offline, false),
      UpdateErrorKind.http => (UpdateStatus.failed, true),
      UpdateErrorKind.malformedManifest ||
      UpdateErrorKind.manifestRejected =>
        (UpdateStatus.failed, false),
      UpdateErrorKind.unsupportedPlatform ||
      UpdateErrorKind.unsupportedArchitecture ||
      UpdateErrorKind.noArtifact ||
      UpdateErrorKind.installFailed ||
      UpdateErrorKind.blocked ||
      UpdateErrorKind.checksumMismatch ||
      UpdateErrorKind.sizeMismatch =>
        (UpdateStatus.failed, true),
      UpdateErrorKind.cancelled => (UpdateStatus.cancelled, false),
      // Handled directly by `download()`, which keeps the progress figure and
      // the resumable offset. Listed here so the switch stays exhaustive.
      UpdateErrorKind.paused => (UpdateStatus.paused, false),
    };
    status = outcome.$1;
    retryable = outcome.$2;
  }

  // ------------------------------------------------------------ download

  /// Downloads (and verifies) the selected artifact. Safe to call from
  /// `updateAvailable`, `mandatory`, `readyToInstall`, `failed` (retry), or
  /// `cancelled`.
  Future<void> download({int resumeFrom = 0}) async {
    if (_busy) return;
    final artifact = selectedArtifact;
    final manifestVersion = manifest?.version;
    if (artifact == null || manifestVersion == null) {
      if (manifest != null && (archLabel == null || resolvedPlatform == null)) {
        status = UpdateStatus.failed;
        errorMessage =
            'No installer is published for your platform or architecture.';
        retryable = false;
      } else {
        status = UpdateStatus.failed;
        errorMessage = 'No update is available for your device.';
        retryable = false;
      }
      notifyListeners();
      return;
    }

    _busy = true;
    _cancelRequested = false;
    _pauseRequested = false;
    // Cleared here so a checkpoint can never leak into a later, unrelated
    // download; the value is re-set only if this run pauses again.
    _resumeOffset = 0;
    progress = resumeFrom > 0
        ? (artifact.size > 0 ? resumeFrom / artifact.size : 0.0)
        : 0.0;
    receivedBytes = resumeFrom;
    totalBytes = resumeFrom > 0 ? artifact.size : null;
    status = UpdateStatus.downloading;
    notifyListeners();

    final fileName = _fileNameFor(artifact, installerKind);
    var attempt = 0;
    // Resume only the first attempt: a retry after a transport failure starts
    // from a clean file, because the dropped connection may have left the
    // partial short. An explicit pause is the one resumable path.
    var offset = resumeFrom;

    try {
      while (true) {
        attempt++;
        try {
          final result = await downloader.download(
            artifact,
            artifactFileName: fileName,
            installerKind: installerKind ?? 'generic',
            onProgress: (received, total) {
              receivedBytes = received;
              totalBytes = total;
              progress = total == null || total <= 0
                  ? 0.0
                  : received / total;
              notifyListeners();
            },
            isCancelled: () => _cancelRequested,
            isPaused: () => _pauseRequested,
            resumeFrom: offset,
          );
          status = UpdateStatus.readyToInstall;
          downloadedPath = result.file.path;
          retryable = false;
          _resumeOffset = 0;
          notifyListeners();
          return;
        } on UpdateException catch (e) {
          if (e.kind == UpdateErrorKind.paused) {
            // Keep the checkpoint and the progress figure so Resume can pick up
            // exactly where this stopped.
            _resumeOffset = e.offset;
            receivedBytes = e.offset;
            status = UpdateStatus.paused;
            errorMessage = null;
            notifyListeners();
            return;
          }
          offset = 0;
          if (e.kind == UpdateErrorKind.cancelled) {
            // A cancelled mandatory download must not demote itself to a
            // normal optional update.
            status = manifest != null && _isMandatory(manifest!)
                ? UpdateStatus.mandatory
                : UpdateStatus.updateAvailable;
            progress = 0;
            notifyListeners();
            return;
          }
          if (attempt >= 3 ||
              (e.kind != UpdateErrorKind.network &&
                  e.kind != UpdateErrorKind.http)) {
            retryableFor(e.kind);
            status = UpdateStatus.failed;
            errorMessage = e.message;
            notifyListeners();
            return;
          }
          // Transient network blip: brief backoff, then retry.
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
    } finally {
      _busy = false;
    }
  }

  /// True while a download is in flight and the user may suspend it.
  bool get canPause => status == UpdateStatus.downloading;

  /// Suspends an in-flight download. The partial file is kept, so [resume]
  /// continues from the same byte instead of re-downloading it.
  ///
  /// Takes effect when the next chunk arrives; a fully stalled connection is
  /// already handled by the downloader's idle watchdog.
  void pause() {
    if (status != UpdateStatus.downloading) return;
    _pauseRequested = true;
    notifyListeners();
  }

  /// Continues a download suspended by [pause].
  Future<void> resume() async {
    if (status != UpdateStatus.paused) return;
    final offset = _resumeOffset;
    _resumeOffset = 0;
    await download(resumeFrom: offset);
  }

  /// A release is mandatory when it declares a [UpdateManifest
  /// .minimumSupportedVersion] newer than the installed version.
  bool _isMandatory(UpdateManifest m) =>
      m.minimumSupportedVersion != null &&
      currentVersion != null &&
      m.minimumSupportedVersion!.compareTo(currentVersion!) > 0;

  /// Records the running server's version fields (from `/api/server/status`).
  /// Non-blocking housekeeping: a missing/unknown server never marks updates
  /// incompatible.
  void noteServerVersion(String? version, String? apiVersion) {
    serverVersion = version;
    serverApiVersion = apiVersion;
    notifyListeners();
  }

  /// True when the latest manifest declares a newer minimum server version than
  /// the running server reports. The UI shows a "update your server" message
  /// instead of letting an incompatible pairing fail obscurely.
  bool get serverIncompatibleWithManifest {
    final minServer = manifest?.minimumServerVersion;
    if (minServer == null) return false;
    final server = SemVersion.tryParse(serverVersion ?? '');
    if (server == null) {
      // We cannot read the server version (e.g. not yet fetched); do not block
      // the update on unknown state.
      return false;
    }
    return server < minServer;
  }

  /// Re-downloads the selected artifact after a failed or cancelled attempt
  /// without re-checking the manifest first.
  Future<void> retryDownload() => download();

  void retryableFor(UpdateErrorKind kind) {
    retryable = kind == UpdateErrorKind.network ||
        kind == UpdateErrorKind.http ||
        kind == UpdateErrorKind.checksumMismatch ||
        kind == UpdateErrorKind.sizeMismatch;
  }

  void cancelDownload() {
    // A paused download has no request in flight to cancel — cancelling it
    // means throwing the checkpoint away.
    if (status == UpdateStatus.paused) {
      unawaited(discardPausedDownload());
      return;
    }
    if (!_busy || status != UpdateStatus.downloading) return;
    _cancelRequested = true;
  }

  /// Throws away a paused download: the partial file is deleted and the state
  /// returns to the one the user can start again from, with no stale progress
  /// left on screen.
  Future<void> discardPausedDownload() async {
    _pauseRequested = false;
    _resumeOffset = 0;
    progress = 0;
    receivedBytes = 0;
    totalBytes = null;
    downloadedPath = null;
    status = manifest != null && _isMandatory(manifest!)
        ? UpdateStatus.mandatory
        : UpdateStatus.updateAvailable;
    notifyListeners();
    final artifact = selectedArtifact;
    if (artifact == null) return;
    await downloader.discardPartial(
      artifactFileName: _fileNameFor(artifact, installerKind),
    );
  }

  // ------------------------------------------------------------- install

  /// Hands the verified installer to the OS/user. Never auto-installs without
  /// explicit action on the platform UI.
  Future<void> install() async {
    final path = downloadedPath;
    if (path == null) {
      status = UpdateStatus.failed;
      errorMessage = 'Download the update first.';
      retryable = false;
      notifyListeners();
      return;
    }
    final platform = resolvedPlatform ?? detector.platform;
    if (!detector.isSupported) {
      status = UpdateStatus.unsupported;
      errorMessage = 'Updates are not supported on this platform.';
      notifyListeners();
      return;
    }

    _busy = true;
    try {
switch (platform) {
case AppPlatform.android:
            final launched = await router.launchAndroidInstaller(path);
            if (!launched) {
              // Most commonly the "install unknown apps" consent for this
              // source is missing. Offer the exact system settings screen.
              status = UpdateStatus.needsUserAction;
              infoMessage =
                  'Android needs your permission to install this update from '
                  'NexaDrive. Grant "Install unknown apps" once in Settings, '
                  'then come back and tap Install again.';
              retryable = false;
            } else {
              status = UpdateStatus.installingHandoff;
              _handoffPending = true;
              infoMessage =
                  'Confirm the installation in the Android dialog, then come '
                  'back to NexaDrive.';
            }
            break;
          case AppPlatform.windows:
            if (installationKind == InstallationKind.portable) {
              await _installPortableWindows(path);
              break;
            }
            final launched = await router.launchWindowsInstaller(path);
            if (!launched) {
              status = UpdateStatus.failed;
              errorMessage =
                  'The installer could not be started. Open the downloaded file '
                  'manually to continue.';
              retryable = false;
            } else {
              status = UpdateStatus.installingHandoff;
              _handoffPending = true;
              infoMessage =
                  'The installer is starting. Follow the Windows prompts, then '
                  'launch Nexusdrive again.';
            }
            break;
          case AppPlatform.linux:
            await _installOnLinux(path);
            break;
          default:
            status = UpdateStatus.unsupported;
            errorMessage = 'Updates are not supported on this platform.';
        }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _installOnLinux(String path) async {
    if (!detector.isSupported) {
      status = UpdateStatus.unsupported;
      errorMessage = 'Updates are not supported on this platform.';
      return;
    }
    final appImage = router.appImagePath();
    if (appImage != null && File(appImage).existsSync()) {
      // Running as an AppImage. Self-replace only when the folder is writable.
      if (!router.dirWritable(appImage)) {
        status = UpdateStatus.readyToInstall;
        infoMessage =
            'The AppImage folder is not writable, so the app cannot replace '
            'itself. Move the AppImage to a writable folder (e.g. your home) '
            'and try again, or use the file shown below to replace it manually.';
        retryable = false;
        notifyListeners();
        return;
      }
      if (await _replaceAppImage(path, appImage)) {
        status = UpdateStatus.completed;
        infoMessage =
            'The update was installed. Restart NexaDrive to use it.';
        retryable = false;
        _clearInstallerCache();
      } else {
        status = UpdateStatus.readyToInstall;
        infoMessage =
            'The AppImage could not be replaced automatically. Use the file '
            'shown below to install it manually.';
        retryable = false;
      }
      return;
    }

    // Not an AppImage: .deb install goes through the system package manager.
    status = UpdateStatus.installingHandoff;
    infoMessage =
        'To complete the update, install the package with your system package '
        'manager:\n\tsudo dpkg -i $path\n\nYou can also open the file with the '
        'system installer now.';
    retryable = false;
  }

  /// Installs a Windows portable build (self-contained folder layout).
  ///
  /// Flow: unpack the verified ZIP into a temporary folder, validate the
  /// payload (main exe + Flutter asset bundle present), then hand off to a
  /// small detached swap helper. A Windows exe cannot replace itself while it
  /// is running, so the helper waits for the app to exit, swaps the files, and
  /// relaunches NexaDrive. If the helper cannot be written/started, the staged
  /// copy is kept and the user is told to restart to finish — the running exe
  /// is never deleted or replaced while executing.
  Future<void> _installPortableWindows(String zipPath) async {
    final exe = router.windowsExecutablePath();
    if (exe == null || exe.isEmpty) {
      status = UpdateStatus.failed;
      errorMessage =
          'Could not locate the application folder for the portable update.';
      retryable = false;
      notifyListeners();
      return;
    }
    final appDir = File(exe).parent;
    if (!appDir.existsSync()) {
      status = UpdateStatus.failed;
      errorMessage = 'The application folder could not be found.';
      retryable = false;
      notifyListeners();
      return;
    }

    // 1. Unpack to a same-volume staging folder so the later swap is atomic
    //    enough (same filesystem move, never a cross-drive copy).
    final staging = Directory(
      '${appDir.path}${Platform.pathSeparator}.nexadrive-stage-${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      if (!await _unpackZip(File(zipPath), staging)) {
        status = UpdateStatus.failed;
        errorMessage = 'The downloaded update could not be unpacked.';
        retryable = false;
        notifyListeners();
        return;
      }

      // 2. Validate the payload before touching anything live.
      final newExe = File(
        '${staging.path}${Platform.pathSeparator}${_baseName(exe)}',
      );
      final assetManifest = File(
        '${staging.path}${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}AssetManifest.bin',
      );
      if (!newExe.existsSync() ||
          newExe.lengthSync() == 0 ||
          !assetManifest.existsSync()) {
        status = UpdateStatus.failed;
        errorMessage =
            'The downloaded update does not look like a valid NexaDrive build.';
        retryable = false;
        notifyListeners();
        return;
      }

      // 3. Write the swap helper next to the app and launch it detached.
      final helper = File(
        '${appDir.path}${Platform.pathSeparator}nexadrive-finish-update.cmd',
      );
      final script = _portableSwapScript(
        staging: staging.path,
        appDir: appDir.path,
        exeName: _baseName(exe),
      );
      try {
        helper.writeAsStringSync(script);
      } catch (_) {
        status = UpdateStatus.failed;
        errorMessage =
            'The update is ready, but the swap helper could not be prepared. '
            'Copy the "data" files from the release ZIP over your app folder '
            'manually, then restart.';
        retryable = false;
        notifyListeners();
        return;
      }
      if (staging.existsSync() && !await router.runDetached(helper.path)) {
        status = UpdateStatus.readyToInstall;
        infoMessage =
            'Download complete — restart NexaDrive to finish the update. '
            'The verified update is staged next to the app and will be applied '
            'the next time it starts.';
        retryable = false;
        notifyListeners();
        return;
      }
      status = UpdateStatus.installingHandoff;
      infoMessage =
          'Download complete — restart NexaDrive to finish the update.';
      retryable = false;
      notifyListeners();
    } catch (_) {
      try {
        staging.deleteSync(recursive: true);
      } catch (_) {}
      status = UpdateStatus.failed;
      errorMessage = 'The update could not be installed.';
      retryable = true;
      notifyListeners();
    }
  }

  /// Generates the detached Windows swap helper. Paths are wrapped in double
  /// quotes and every literal `%` is doubled (batch expands `%VAR%` at parse
  /// time), so a path such as `C:\Users\50%Tax` cannot corrupt or escape the
  /// script.
  static String _portableSwapScript({
    required String staging,
    required String appDir,
    required String exeName,
  }) {
    String batchEscape(String value) => value.replaceAll('%', '%%');
    final src = batchEscape(staging);
    final dir = batchEscape(appDir);
    final appExe = batchEscape('$appDir$Platform.pathSeparator$exeName');
    return '@echo off\r\n'
        'REM NexaDrive portable updater: waits for the app to exit, swaps the\r\n'
        'REM staged build into place, relaunches, then removes itself.\r\n'
        'setlocal\r\n'
        'set "UPDATE_SRC=$src"\r\n'
        'set "APP_DIR=$dir"\r\n'
        'set "APP_EXE=$appExe"\r\n'
        ':wait\r\n'
        'tasklist /FI "IMAGENAME eq $exeName" 2>NUL | find /I "$exeName" >NUL\r\n'
        'if not errorlevel 1 (\r\n'
        '  timeout /t 2 /nobreak >NUL\r\n'
        '  goto wait\r\n'
        ')\r\n'
        'xcopy "%UPDATE_SRC%\\*" "%APP_DIR%\\" /y /e /q /h /r /i >NUL\r\n'
        'rmdir /s /q "%UPDATE_SRC%" 2>NUL\r\n'
        'start "" "%APP_EXE%"\r\n'
        'del "%~f0" 2>NUL\r\n';
  }

  /// Extracts a ZIP archive into [target], returning false on any failure.
  /// Path traversal entries are rejected before anything touches disk.
  Future<bool> _unpackZip(File zip, Directory target) async {
    try {
      final bytes = zip.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      for (final entry in archive) {
        final name = entry.name.replaceAll('\\', '/');
        final parts = name.split('/');
        if (parts.any((p) => p == '..') ||
            name.startsWith('/') ||
            name.contains(':') ||
            name.startsWith('~')) {
          return false;
        }
      }
      if (target.existsSync()) target.deleteSync(recursive: true);
      target.createSync(recursive: true);
      for (final entry in archive) {
        final outPath = '${target.path}${Platform.pathSeparator}${entry.name}';
        if (entry.isFile) {
          final out = File(outPath);
          out.parent.createSync(recursive: true);
          out.writeAsBytesSync(entry.content as List<int>);
        } else if (entry.isDirectory) {
          Directory(outPath).createSync(recursive: true);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Android "Install unknown apps" screen for this app so the
  /// user can grant per-source install consent. No-op off Android.
  Future<void> requestInstallPermission() async {
    try {
      await router.openInstallPermissionSettings();
    } catch (_) {
      // Screen unavailable on this device; the UI keeps its explanation.
    }
  }

  /// Launches the desktop "open with" handler for a downloaded .deb.
  Future<bool> openDebWithSystemInstaller() async {
    final path = downloadedPath;
    if (path == null) return false;
    return router.openWithSystemInstaller(path);
  }

  /// Atomic swap of the running AppImage (old → .bak, new → live, drop .bak).
  Future<bool> _replaceAppImage(String downloaded, String live) async {
    // The running image is [live] (e.g. NexaDrive-1.1.0-linux-x86_64.AppImage
    // in a writable folder). The verified download is [downloaded] in the
    // update cache. The new bytes first fully replace a staging copy (never
    // the running image), then that staging file atomically renames over the
    // live path. A Linux rename(2) over a running binary is safe: the kernel
    // keeps the old inode alive for the executing process.
    final liveFile = File(live);
    final dir = liveFile.parent.path;
    final stage = File('$dir/${_baseName(downloaded)}.new');
    final backup = File('$dir/${_baseName(downloaded)}.bak');
    try {
      // Stage: copy to a fresh temp name, then make executable.
      try {
        if (stage.existsSync()) stage.deleteSync();
      } catch (_) {}
      await File(downloaded).copy(stage.path);
      final chmod = await Process.run('chmod', ['+x', stage.path]);
      if (chmod.exitCode != 0) {
        throw const UpdateException(
          UpdateErrorKind.installFailed,
          'Could not make the updated AppImage executable.',
        );
      }
      // Rollback anchor: move the old image aside BEFORE replacing it.
      final liveExisted = liveFile.existsSync();
      if (liveExisted) {
        try {
          if (backup.existsSync()) backup.deleteSync();
        } catch (_) {}
        await liveFile.rename(backup.path);
      }
      try {
        await stage.rename(liveFile.path);
      } catch (_) {
        // Rollback: put the original image back before giving up.
        if (liveExisted && backup.existsSync() && !liveFile.existsSync()) {
          await backup.rename(liveFile.path);
        }
        rethrow;
      }
      // Success: drop the backup and the consumed download.
      try {
        if (backup.existsSync()) backup.deleteSync();
      } catch (_) {}
      try {
        final src = File(downloaded);
        if (src.existsSync()) src.deleteSync();
      } catch (_) {}
      return true;
    } catch (_) {
      try {
        if (stage.existsSync()) stage.deleteSync();
      } catch (_) {}
      // Leave any [backup] in place: it is either a valid copy of the
      // previous working image or the only remaining copy of it.
      return false;
    }
  }

  // ---------------------------------------------------------- reconciliation

  /// Call on app resume. If the user completed an Android/Windows install
  /// while out of the app, confirm success and refresh state.
  Future<void> reconcileAfterResume() async {
    if (!_handoffPending && status != UpdateStatus.installingHandoff) return;
    final target = manifest?.version;
    if (target == null) {
      _handoffPending = false;
      return;
    }

    final installed =
        SemVersion.tryParse(await loadCurrentVersion()) ??
            currentVersion ??
            const SemVersion(0, 0, 0);
    if (installed.compareTo(target) >= 0) {
      status = UpdateStatus.completed;
      _handoffPending = false;
      infoMessage = 'The update is installed.';
      retryable = false;
      _clearInstallerCache();
    } else {
      // APK not applied yet (user came back to the app first). Resume the
      // Update Center in a state where they can finish or retry.
      status = _isMandatory(manifest!)
          ? UpdateStatus.mandatory
          : UpdateStatus.updateAvailable;
      infoMessage =
          'The update is not installed yet. Please finish the setup, or '
          'download again.';
      retryable = false;
    }
if (status == UpdateStatus.completed) {
        _clearInstallerCache();
      } else {
        try {
          await UpdateCache.prune();
        } catch (_) {}
      }
      notifyListeners();
    }

  /// Frees the on-disk installer cache. Nothing is kept after a confirmed
  /// install: the consumed APK/ZIP/AppImage, any stray `.part` files, and any
  /// older downloaded installers are removed. Best-effort — a locked or
  /// missing file never breaks the success path.
  void _clearInstallerCache() {
    downloadedPath = null;
    unawaited(
      UpdateCache.clearAll().catchError((Object _) {}),
    );
  }

  /// Reloads the installed version from the OS and refreshes bookkeeping.
  Future<void> refreshInstalledVersion() async {
    final raw = await loadCurrentVersion();
    currentVersion = SemVersion.tryParse(raw) ?? const SemVersion(0, 0, 0);
    notifyListeners();
  }

  // ---------------------------------------------------------------- helpers

  static String _baseName(String path) =>
      path.split(Platform.pathSeparator).last.split('/').last;

  /// Resolves a deterministic artifact kind for Linux installs whose layout
  /// could not be auto-detected, honoring the user's explicit choice.
  static String? _defaultArtifactKindFor(
    UpdateManifest manifest,
    AppPlatform platform,
    String arch,
    String? explicit,
  ) {
    if (platform != AppPlatform.linux) return null;
    final kinds = manifest.artifacts['linux']?[arch];
    if (kinds == null || kinds.isEmpty) return null;
    if (explicit != null && kinds.containsKey(explicit)) return explicit;
    if (kinds.containsKey('appimage')) return 'appimage';
    if (kinds.containsKey('deb')) return 'deb';
    return kinds.keys.first;
  }

  /// Lets the user pick the Linux package (AppImage vs. .deb) when the install
  /// type could not be auto-detected. No-op off Linux or when nothing is
  /// selected yet.
  Future<void> chooseLinuxPackage(String kind) async {
    if (kind != 'appimage' && kind != 'deb') return;
    if (resolvedPlatform != AppPlatform.linux ||
        manifest == null ||
        archLabel == null) {
      return;
    }
    linuxPackageChoice = kind;
    selectedArtifact = manifest!.artifacts['linux']?[archLabel!]?[kind];
    installerKind = kind;
    downloadedPath = null;
    progress = 0;
    status = _isMandatory(manifest!)
        ? UpdateStatus.mandatory
        : UpdateStatus.updateAvailable;
    notifyListeners();
  }

  static String _fileNameFor(ArtifactInfo artifact, String? kind) {
    final uri = Uri.tryParse(artifact.url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.isNotEmpty) return last;
    }
    final ext = switch (kind) {
      'apk' => 'apk',
      'installer' => 'exe',
      'appimage' => 'AppImage',
      'deb' => 'deb',
      'zip' => 'zip',
      _ => 'bin',
    };
    return 'nexadrive-update.$ext';
  }
}