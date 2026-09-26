import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_typography.dart';
import '../../../update/app_platform.dart';
import '../../../update/update_controller.dart';
import '../../widgets/one_ui_page.dart';

/// The Update Center, rebuilt from scratch.
///
/// Architecture: the screen is a pure view of [UpdateController]. It never
/// performs an update operation itself — every button delegates to a
/// controller method, and every visual state maps 1:1 onto an
/// [UpdateStatus].
///
/// Typography contract: every text carries an explicit [AppTextStyle] token.
/// Nothing relies on an inherited [DefaultTextStyle], so no text can
/// accidentally render with a decoration it never asked for.
class UpdateCenterScreen extends StatelessWidget {
  final UpdateController controller;

  const UpdateCenterScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final status = controller.status;

        return OneUiPage(
          title: 'Update center',
          subtitle: _subtitleText(controller, status),
          scrollable: true,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VersionPanel(controller: controller),
              const SizedBox(height: AppDimens.space16),
              _ActionArea(controller: controller, status: status),
              if (controller.manifest != null) ...[
                const SizedBox(height: AppDimens.space24),
                _ReleaseDetails(controller: controller),
              ],
              if (controller.manifest != null &&
                  !controller.manifest!.releaseNotes.isEmpty) ...[
                const SizedBox(height: AppDimens.space24),
                _ReleaseNotes(controller: controller),
              ],
              const SizedBox(height: AppDimens.space24),
            ],
          ),
        );
      },
    );
  }
}

/// The page subtitle text: one line that always answers "what is happening".
String _subtitleText(UpdateController controller, UpdateStatus status) {
  switch (status) {
    case UpdateStatus.idle:
      return controller.latestKnownLabel != null
          ? 'Latest known version ${controller.latestKnownLabel}'
          : 'Check GitHub Releases for a newer version';
    case UpdateStatus.checking:
      return 'Contacting the release server…';
    case UpdateStatus.downloading:
      return 'Downloading the update…';
    case UpdateStatus.verifying:
      return 'Verifying the download…';
    case UpdateStatus.upToDate:
      final v = controller.manifestVersionLabel;
      return v != null
          ? 'You are on the latest version $v.'
          : 'Everything is up to date.';
    case UpdateStatus.updateAvailable:
      return 'A new version is ready to download.';
    case UpdateStatus.mandatory:
      return 'This release is required to keep using NexaDrive.';
    case UpdateStatus.paused:
      return 'Paused — your progress is kept.';
    case UpdateStatus.readyToInstall:
      return 'The verified installer is ready.';
    case UpdateStatus.installingHandoff:
      return 'Finish the installation, then come back.';
    case UpdateStatus.completed:
      return 'The update is installed.';
    case UpdateStatus.cancelled:
      return 'The download was cancelled.';
    case UpdateStatus.failed:
      return 'The update could not be completed.';
    case UpdateStatus.offline:
      return 'Offline — the release list is unavailable.';
    case UpdateStatus.unsupported:
      return 'Updates are not supported on this setup.';
    case UpdateStatus.needsUserAction:
      return 'Android needs permission to install the update.';
  }
}

/// The hero status card: CURRENT VERSION → LATEST VERSION with a status
/// ribbon and, while working, an integrated progress bar.
class _VersionPanel extends StatelessWidget {
  final UpdateController controller;

  const _VersionPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final status = controller.status;
    final (icon, headline, color) = _visuals(status, brightness);
    final working = status == UpdateStatus.checking ||
        status == UpdateStatus.downloading ||
        status == UpdateStatus.verifying;

    return Container(
      padding: const EdgeInsets.all(AppDimens.space20),
      decoration: BoxDecoration(
        color: AppColors.surfaceFor(brightness),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: brightness == Brightness.dark
            ? Border.all(color: const Color(0x1FFFFFFF))
            : null,
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowColorSoft,
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusBadge(icon: icon, color: color, spinning: working),
              const SizedBox(width: AppDimens.space12),
              Expanded(
                child: Text(
                  headline,
                  style: AppTextStyle.sectionHeader.copyWith(
                    color: AppColors.textPrimaryFor(brightness),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space16),
          _VersionLine(controller: controller, status: status),
          AnimatedSize(
            duration: AppMotion.resolve(context, AppMotion.fast),
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: working || status == UpdateStatus.paused
                ? _ProgressBar(controller: controller, color: color)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  (IconData, String, Color) _visuals(UpdateStatus status, Brightness b) {
    final accent = AppColors.accentFor(b);
    final success = AppColors.successFor(b);
    final warning = AppColors.warningFor(b);
    final error = AppColors.errorFor(b);
    return switch (status) {
      UpdateStatus.idle => (
          Icons.system_update_alt_rounded,
          'Not checked yet',
          accent,
        ),
      UpdateStatus.checking => (
          Icons.cloud_sync_outlined,
          'Checking for updates',
          accent,
        ),
      UpdateStatus.upToDate => (
          Icons.check_circle_rounded,
          'Up to date',
          success,
        ),
      UpdateStatus.updateAvailable => (
          Icons.system_update_alt_rounded,
          'Update available',
          accent,
        ),
      UpdateStatus.mandatory => (
          Icons.error_outline_rounded,
          'Mandatory update',
          warning,
        ),
      UpdateStatus.downloading => (
          Icons.download_rounded,
          'Downloading',
          accent,
        ),
      UpdateStatus.paused => (
          Icons.pause_circle_outline_rounded,
          'Download paused',
          warning,
        ),
      UpdateStatus.verifying => (
          Icons.verified_rounded,
          'Verifying download',
          accent,
        ),
      UpdateStatus.readyToInstall => (
          Icons.inventory_2_outlined,
          'Ready to install',
          accent,
        ),
      UpdateStatus.installingHandoff => (
          Icons.handyman_outlined,
          'Continue in the installer',
          accent,
        ),
      UpdateStatus.completed => (
          Icons.check_circle_rounded,
          'Installed',
          success,
        ),
      UpdateStatus.failed => (Icons.error_rounded, 'Update failed', error),
      UpdateStatus.cancelled => (
          Icons.cancel_outlined,
          'Cancelled',
          warning,
        ),
      UpdateStatus.offline => (Icons.cloud_off_rounded, 'Offline', warning),
      UpdateStatus.unsupported => (
          Icons.priority_high_rounded,
          'Unsupported',
          warning,
        ),
      UpdateStatus.needsUserAction => (
          Icons.lock_outline_rounded,
          'Permission needed',
          warning,
        ),
    };
  }
}

/// The colored status icon with a gentle breathe animation while a check or
/// download is in flight. Respects the reduced-motion setting.
class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool spinning;

  const _StatusBadge({
    required this.icon,
    required this.color,
    required this.spinning,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: AppDimens.iconTileLarge,
      height: AppDimens.iconTileLarge,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppDimens.radiusInner),
      ),
      child: Icon(icon, color: color, size: AppDimens.iconMedium),
    );
    // Deliberately static: an in-flight indicator already communicates work
    // (determinate bar / spinner below), so the icon never animates
    // continuously. Infinite pulses defeat pumpAndSettle in tests and cost
    // frames for no informational gain.
    return tile;
  }
}

/// CURRENT → LATEST figures. Every number is its own explicit style; no
/// inherited decoration can reach them.
class _VersionLine extends StatelessWidget {
  final UpdateController controller;
  final UpdateStatus status;

  const _VersionLine({required this.controller, required this.status});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final current = controller.currentVersion?.toString() ?? '—';
    final latest = controller.manifestVersionLabel;
    final showLatest = latest != null &&
        (status == UpdateStatus.updateAvailable ||
            status == UpdateStatus.mandatory ||
            status == UpdateStatus.downloading ||
            status == UpdateStatus.paused ||
            status == UpdateStatus.verifying ||
            status == UpdateStatus.readyToInstall ||
            status == UpdateStatus.installingHandoff ||
            status == UpdateStatus.cancelled ||
            status == UpdateStatus.failed);

    // A Wrap, not a Row: on a very narrow window (or a test's 1em-wide
    // glyph fallback font) the figures flow onto a second line instead of
    // overflowing. Spacing matches the previous inline arrow rhythm.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: AppDimens.space16,
      runSpacing: AppDimens.space12,
      children: [
        _VersionFigure(
          label: 'CURRENT',
          value: current,
          color: AppColors.textSecondaryFor(brightness),
        ),
        if (showLatest)
          _VersionFigure(
            label: 'LATEST',
            value: latest,
            color: AppColors.textPrimaryFor(brightness),
          ),
      ],
    );
  }
}

class _VersionFigure extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _VersionFigure({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyle.micro.copyWith(
            color: AppColors.textTertiaryFor(Theme.of(context).brightness),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: AppDimens.space2),
        Text(
          'v$value',
          style: AppTextStyle.metricValue.copyWith(color: color),
        ),
      ],
    );
  }
}

/// The progress bar with byte counts, used for download and pause states.
class _ProgressBar extends StatelessWidget {
  final UpdateController controller;
  final Color color;

  const _ProgressBar({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    final received = controller.receivedBytes;
    final total = controller.totalBytes;
    final downloading = controller.status == UpdateStatus.downloading;
    final paused = controller.status == UpdateStatus.paused;
    final inProgress = downloading && controller.progress > 0;

    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: controller.progress.clamp(0.0, 1.0)),
              duration: AppMotion.resolve(context, AppMotion.normal),
              curve: AppMotion.standard,
              builder: (context, value, _) => LinearProgressIndicator(
                // Determinate whenever a real fraction is known (including a
                // paused download — nothing is in flight, so an
                // indeterminate spinner would lie).
                value: inProgress || paused ? value : null,
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.space8),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _progressLabel(received, total, downloading),
                    style: AppTextStyle.caption.copyWith(
                      color: AppColors.textSecondaryFor(
                          Theme.of(context).brightness),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (downloading)
                Text(
                  '${(controller.progress.clamp(0.0, 1.0) * 100).round()}%',
                  style: AppTextStyle.chipLabel.copyWith(
                    color:
                        AppColors.textPrimaryFor(Theme.of(context).brightness),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _progressLabel(int received, int? total, bool downloading) {
    if (controller.status == UpdateStatus.paused) {
      final at = total != null && total > 0
          ? '${_bytes(received)} of ${_bytes(total)}'
          : _bytes(received);
      return 'Paused at $at';
    }
    if (!downloading) return 'This usually takes a moment.';
    if (total != null) return '${_bytes(received)} of ${_bytes(total)}';
    return _bytes(received);
  }
}

/// The single action area: exactly one primary affordance per state plus,
/// where the flow needs it, one secondary affordance. Never two primaries.
class _ActionArea extends StatelessWidget {
  final UpdateController controller;
  final UpdateStatus status;

  const _ActionArea({required this.controller, required this.status});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._panels(context),
        ..._primaryAction(context),
        ..._secondaryActions(context),
      ],
    );
  }

  List<Widget> _panels(BuildContext context) {
    switch (status) {
      case UpdateStatus.failed:
        return [
          _Notice(
            tone: _NoticeTone.error,
            text: controller.errorMessage ??
                'The update could not be completed. Try again, or check the '
                    'release page.',
          ),
          const SizedBox(height: AppDimens.space12),
        ];
      case UpdateStatus.offline:
        return [
          const _Notice(
            tone: _NoticeTone.warning,
            text: 'NexaDrive could not reach the release server. Check the '
                'network connection and try again.',
          ),
          const SizedBox(height: AppDimens.space12),
        ];
      case UpdateStatus.unsupported:
        return [
          _Notice(
            tone: _NoticeTone.warning,
            text: controller.errorMessage ??
                'Updates are not supported on this platform or install type.',
          ),
          const SizedBox(height: AppDimens.space12),
        ];
      case UpdateStatus.needsUserAction:
        return [
          _Notice(
            tone: _NoticeTone.warning,
            text: controller.infoMessage ??
                'Android needs your permission to install this update from '
                    'NexaDrive. Grant "Install unknown apps" once in '
                    'Settings, then tap Install again.',
          ),
          const SizedBox(height: AppDimens.space12),
        ];
      case UpdateStatus.installingHandoff:
        return [
          _Notice(
            tone: _NoticeTone.info,
            text: controller.infoMessage ??
                'Follow the prompts, then come back to NexaDrive.',
          ),
          const SizedBox(height: AppDimens.space12),
        ];
      case UpdateStatus.readyToInstall:
        if (controller.installerKind == 'deb' &&
            controller.downloadedPath != null) {
          return [
            _Notice(
              tone: _NoticeTone.info,
              text: 'Install the package with your system package manager:\n'
                  'sudo dpkg -i ${controller.downloadedPath}',
            ),
            const SizedBox(height: AppDimens.space12),
          ];
        }
        return const [];
      case UpdateStatus.updateAvailable:
      case UpdateStatus.mandatory:
        if (controller.selectedArtifact == null) {
          return [
            _Notice(
              tone: _NoticeTone.warning,
              text: 'No installer is published for this device yet '
                  '(${controller.archLabel ?? 'your system'}). Let the '
                  'developer know you need a build for this platform.',
            ),
            const SizedBox(height: AppDimens.space12),
          ];
        }
        // Unknown Linux layout: let the user pick the package kind.
        if (controller.resolvedPlatform == AppPlatform.linux &&
            controller.installationKind != null &&
            (controller.installationKind == InstallationKind.unknown ||
                controller.installationKind == InstallationKind.source)) {
          return [
            const _Notice(
              tone: _NoticeTone.warning,
              text: 'We could not tell how NexaDrive is installed here. '
                  'Choose your Linux package to continue.',
            ),
            const SizedBox(height: AppDimens.space8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => controller.chooseLinuxPackage('appimage'),
                    icon: const Icon(Icons.rocket_launch_rounded,
                        size: AppDimens.iconSmall),
                    label: const Text('AppImage'),
                  ),
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => controller.chooseLinuxPackage('deb'),
                    icon: const Icon(Icons.inventory_2_outlined,
                        size: AppDimens.iconSmall),
                    label: const Text('DEB'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space12),
          ];
        }
        return const [];
      default:
        return const [];
    }
  }

  /// The one primary button for the state, or nothing while work is in
  /// flight (the progress surface takes over).
  List<Widget> _primaryAction(BuildContext context) {
    switch (status) {
      case UpdateStatus.idle:
      case UpdateStatus.upToDate:
      case UpdateStatus.completed:
        return [
          _PrimaryButton(
            onPressed: () => controller.checkForUpdates(manual: true),
            label: status == UpdateStatus.idle
                ? 'Check for updates'
                : 'Check again',
          ),
        ];
      case UpdateStatus.checking:
      case UpdateStatus.verifying:
      case UpdateStatus.downloading:
        return const [];
      case UpdateStatus.updateAvailable:
      case UpdateStatus.cancelled:
        return [
          _PrimaryButton(
            onPressed: controller.selectedArtifact == null
                ? null
                : controller.download,
            label: 'Download & install',
          ),
        ];
      case UpdateStatus.mandatory:
        return [
          _PrimaryButton(
            onPressed: controller.selectedArtifact == null
                ? null
                : controller.download,
            label: 'Download now',
          ),
        ];
      case UpdateStatus.paused:
        return [
          _PrimaryButton(
            onPressed: controller.resume,
            label: 'Resume download',
            icon: Icons.play_arrow_rounded,
          ),
        ];
      case UpdateStatus.readyToInstall:
        return [
          _PrimaryButton(
            onPressed: controller.install,
            label: _installLabel(),
          ),
        ];
      case UpdateStatus.installingHandoff:
        return [
          _PrimaryButton(
            onPressed: controller.reconcileAfterResume,
            label: 'I completed the install',
          ),
        ];
      case UpdateStatus.failed:
      case UpdateStatus.offline:
      case UpdateStatus.unsupported:
      case UpdateStatus.needsUserAction:
        final wasDownloading = controller.selectedArtifact != null &&
            controller.downloadedPath == null &&
            controller.status == UpdateStatus.failed;
        return [
          _PrimaryButton(
            onPressed: wasDownloading && status == UpdateStatus.failed
                ? controller.retryDownload
                : () => controller.checkForUpdates(manual: true),
            label: wasDownloading && status == UpdateStatus.failed
                ? 'Retry download'
                : 'Try again',
          ),
        ];
    }
  }

  List<Widget> _secondaryActions(BuildContext context) {
    final actions = <Widget>[];
    switch (status) {
      case UpdateStatus.needsUserAction:
        actions.add(const SizedBox(height: AppDimens.space8));
        actions.add(
          OutlinedButton.icon(
            onPressed: controller.requestInstallPermission,
            icon: const Icon(Icons.settings_rounded, size: AppDimens.iconSmall),
            label: const Text('Open install permission settings'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppDimens.touchTargetLarge),
            ),
          ),
        );
      case UpdateStatus.readyToInstall:
        if (controller.installerKind == 'deb' &&
            controller.downloadedPath != null) {
          actions.add(const SizedBox(height: AppDimens.space8));
          actions.add(
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.openDebWithSystemInstaller,
                    icon: const Icon(Icons.open_in_new_rounded,
                        size: AppDimens.iconSmall),
                    label: const Text('Open package'),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy install command',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(
                        text: 'sudo dpkg -i ${controller.downloadedPath}'),
                  ),
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          );
        }
      case UpdateStatus.idle:
      case UpdateStatus.upToDate:
      case UpdateStatus.completed:
      case UpdateStatus.offline:
        actions.add(const SizedBox(height: AppDimens.space10));
        actions.add(
          Center(
            child: Text(
              controller.latestKnownLabel != null
                  ? 'Last checked: ${controller.lastCheckLabel}'
                  : 'Latest known version is shown automatically.',
              style: AppTextStyle.caption.copyWith(
                color: AppColors.textTertiaryFor(Theme.of(context).brightness),
              ),
            ),
          ),
        );
      default:
        break;
    }
    return actions;
  }

  String _installLabel() {
    switch (controller.installerKind) {
      case 'apk':
      case 'installer':
        return 'Install now';
      case 'appimage':
        return 'Apply update';
      case 'zip':
      case 'portable':
        return 'Update portable app';
      default:
        return 'Finish install';
    }
  }
}

/// The one primary action button, shared by every state so the shape stays
/// pixel-identical everywhere. Exactly one instance is ever on screen.
class _PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;

  const _PrimaryButton({
    required this.onPressed,
    required this.label,
    this.icon,
  });

  static final ButtonStyle _style = FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(AppDimens.touchTargetLarge),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
    ),
    textStyle: AppTextStyle.button,
  );

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    if (icon == null) {
      return FilledButton(
        onPressed: onPressed,
        style: _style,
        child: Text(label),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: _style,
      icon: Icon(icon, size: AppDimens.iconSmall),
      label: Text(label),
    );
  }
}

/// The tonal notice used for errors, explanations and hand-off guidance.
enum _NoticeTone { info, warning, error }

class _Notice extends StatelessWidget {
  final _NoticeTone tone;
  final String text;

  const _Notice({required this.tone, required this.text});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final (color, icon) = switch (tone) {
      _NoticeTone.info => (
          AppColors.infoFor(brightness),
          Icons.info_outline_rounded,
        ),
      _NoticeTone.warning => (
          AppColors.warningFor(brightness),
          Icons.warning_amber_rounded,
        ),
      _NoticeTone.error => (
          AppColors.errorFor(brightness),
          Icons.error_outline_rounded,
        ),
    };
    return Container(
      padding: const EdgeInsets.all(AppDimens.space16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppDimens.radiusTile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: AppDimens.iconMedium),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Text(
              text,
              style: AppTextStyle.rowSubtitle.copyWith(
                color: AppColors.textPrimaryFor(brightness),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Release details as a clean definition list.
class _ReleaseDetails extends StatelessWidget {
  final UpdateController controller;

  const _ReleaseDetails({required this.controller});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final manifest = controller.manifest!;
    final size = controller.selectedArtifact?.size;
    final date = manifest.releaseDate.toLocal();

    return _Section(
      header: 'RELEASE DETAILS',
      children: [
        _DefinitionRow(label: 'Version', value: manifest.version.toString()),
        _DefinitionRow(
          label: 'Channel',
          value: manifest.prerelease ? 'Pre-release' : 'Stable release',
        ),
        _DefinitionRow(label: 'Published', value: _dateLabel(date)),
        if (size != null)
          _DefinitionRow(label: 'Download size', value: _bytes(size)),
        if (manifest.minimumSupportedVersion != null)
          _DefinitionRow(
            label: 'Minimum supported',
            value: manifest.minimumSupportedVersion!.toString(),
          ),
        if (manifest.minimumServerVersion != null) ...[
          _DefinitionRow(
            label: 'Minimum server',
            value: manifest.minimumServerVersion!.toString(),
            valueColor: controller.serverIncompatibleWithManifest
                ? AppColors.errorFor(brightness)
                : null,
          ),
          if (controller.serverIncompatibleWithManifest)
            const Padding(
              padding: EdgeInsets.only(top: AppDimens.space8),
              child: _Notice(
                tone: _NoticeTone.error,
                text: 'The connected server is older than this release '
                    'requires. Update the server first, then install this '
                    'version of the app.',
              ),
            ),
        ],
      ],
    );
  }
}

/// Structured release notes: section label + plain-text bullets.
class _ReleaseNotes extends StatelessWidget {
  final UpdateController controller;

  const _ReleaseNotes({required this.controller});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final sections = controller.manifest!.releaseNotes.sections;

    return _Section(
      header: 'WHAT\u2019S NEW',
      children: [
        for (final entry in sections.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppDimens.space8,
              bottom: AppDimens.space6,
            ),
            child: Text(
              entry.key,
              style: AppTextStyle.listHeader.copyWith(
                color: AppColors.accentTextFor(brightness),
                letterSpacing: 0.6,
              ),
            ),
          ),
          for (final item in entry.value)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppDimens.space4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accentFor(brightness)
                            .withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimens.space12),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTextStyle.rowSubtitle.copyWith(
                        color: AppColors.textPrimaryFor(brightness),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// A titled content block used by details and notes. The header is a plain
/// micro-label — deliberately not a link, never underlined.
class _Section extends StatelessWidget {
  final String header;
  final List<Widget> children;

  const _Section({required this.header, required this.children});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(AppDimens.space16),
      decoration: BoxDecoration(
        color: AppColors.surfaceFor(brightness),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: brightness == Brightness.dark
            ? Border.all(color: const Color(0x1FFFFFFF))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: AppTextStyle.listHeader.copyWith(
              color: AppColors.textTertiaryFor(brightness),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppDimens.space12),
          ...children,
        ],
      ),
    );
  }
}

/// label/value row with independent text wrapping, so a long value can never
/// collide with its label on a narrow window.
class _DefinitionRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DefinitionRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: AppTextStyle.caption.copyWith(
                color: AppColors.textSecondaryFor(brightness),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyle.rowSubtitle.copyWith(
                color: valueColor ?? AppColors.textPrimaryFor(brightness),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

String _dateLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}
