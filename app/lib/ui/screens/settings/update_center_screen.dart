import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_typography.dart';
import '../../../update/app_platform.dart';
import '../../../update/update_controller.dart';
import '../../widgets/one_ui_grouped_list.dart';
import '../../widgets/one_ui_page.dart';

/// The Update Center: checks GitHub Releases through the signed manifest,
/// downloads a verified installer, and hands it to the platform's installer.
///
/// Layout is the standard One UI grouped-list rhythm: a "Status" list row
/// answers `where am I`, one primary action moves the story forward, and
/// "Release details" / "What's new" groups add context. No banner boxes.
class UpdateCenterScreen extends StatelessWidget {
  final UpdateController controller;

  const UpdateCenterScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final brightness = Theme.of(context).brightness;
        final status = controller.status;

        return OneUiPage(
          title: 'Update center',
          subtitle: _subtitle(status, brightness),
          scrollable: true,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusGroup(controller: controller),
              const SizedBox(height: AppDimens.space20),
              _ActionArea(controller: controller),
              if (controller.hasUpdate && controller.selectedArtifact == null) ...[
                const SizedBox(height: AppDimens.space12),
                _NoticePanel(
                  icon: Icons.unfold_more_rounded,
                  color: AppColors.warningFor(brightness),
                  text:
                      'No installer is published for this device yet '
                      '(${controller.archLabel ?? 'your system'}). Let the '
                      'developer know you need a build for this platform.',
                ),
              ],
              if (controller.resolvedPlatform == AppPlatform.linux &&
                  controller.hasUpdate &&
                  (controller.installationKind == null ||
                      controller.installationKind ==
                          InstallationKind.unknown) &&
                  controller.selectedArtifact == null) ...[
                const SizedBox(height: AppDimens.space12),
                _NoticePanel(
                  icon: Icons.widgets_outlined,
                  color: AppColors.warningFor(brightness),
                  text:
                      'We could not tell how NexaDrive is installed here. '
                      'Choose your Linux package to continue.',
                ),
                const SizedBox(height: AppDimens.space10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => controller.chooseLinuxPackage('appimage'),
                        icon: const Icon(Icons.rocket_launch_rounded),
                        label: const Text('AppImage'),
                      ),
                    ),
                    const SizedBox(width: AppDimens.space12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => controller.chooseLinuxPackage('deb'),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('DEB'),
                      ),
                    ),
                  ],
                ),
              ],
              if (status == UpdateStatus.installingHandoff) ...[
                const SizedBox(height: AppDimens.space12),
                _InstallHint(controller: controller),
              ],
              if (status == UpdateStatus.readyToInstall &&
                  controller.installerKind == 'deb') ...[
                const SizedBox(height: AppDimens.space12),
                _DebActions(controller: controller),
              ],
              if (controller.manifest != null) ...[
                const SizedBox(height: AppDimens.space24),
                _DetailsGroup(controller: controller),
              ],
              if (controller.manifest != null &&
                  !controller.manifest!.releaseNotes.isEmpty) ...[
                const SizedBox(height: AppDimens.space24),
                _ReleaseNotesGroup(controller: controller),
              ],
              const SizedBox(height: AppDimens.space24),
            ],
          ),
        );
      },
    );
  }

  String _subtitle(UpdateStatus status, Brightness brightness) {
    switch (status) {
      case UpdateStatus.idle:
        return controller.latestKnownLabel != null
            ? 'Latest known version ${controller.latestKnownLabel}'
            : 'Check GitHub Releases for a newer version';
      case UpdateStatus.checking:
        return 'Contacting the release server…';
      case UpdateStatus.downloading:
        return 'Downloading…';
      case UpdateStatus.verifying:
        return 'Verifying the download…';
      case UpdateStatus.upToDate:
        return controller.manifestVersionLabel != null
            ? 'You are on the latest version ${controller.manifestVersionLabel}.'
            : 'Everything is up to date.';
      case UpdateStatus.updateAvailable:
        return 'A new version is ready to download.';
      case UpdateStatus.mandatory:
        return 'This release is required to keep using NexaDrive.';
      case UpdateStatus.completed:
        return 'The update is installed.';
      case UpdateStatus.cancelled:
        return 'The download was cancelled.';
      case UpdateStatus.failed:
        return 'The update could not be completed.';
      case UpdateStatus.offline:
        return 'Offline — the release list is unavailable.';
      case UpdateStatus.paused:
        return 'Paused — your progress is kept, resume whenever you like.';
      case UpdateStatus.readyToInstall:
        return 'The verified installer is ready.';
      case UpdateStatus.installingHandoff:
        return 'Finish the installation in the system dialog.';
      case UpdateStatus.unsupported:
        return 'Updates are not supported on this platform.';
      case UpdateStatus.needsUserAction:
        return 'Android needs permission to install the update.';
    }
  }
}

/// The status section: a normal One UI row shows the current decision, with a
/// quiet progress bar below it while the controller is working.
class _StatusGroup extends StatelessWidget {
  final UpdateController controller;
  const _StatusGroup({required this.controller});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final status = controller.status;
    final (icon, headline, color) = _statusVisual(status, brightness);
    final working = status == UpdateStatus.checking ||
        status == UpdateStatus.downloading ||
        status == UpdateStatus.verifying;

    return OneUiGroupedList(
      header: 'Status',
      children: [
        OneUiGroupTile(
          icon: icon,
          iconColor: color,
          iconBackground: color.withValues(alpha: 0.14),
          title: headline,
          subtitle: _statusLine(controller),
          showChevron: false,
          onTap: null,
        ),
        if (working)
          _ProgressRow(
            controller: controller,
            color: color,
            inProgress: status == UpdateStatus.downloading &&
                controller.progress > 0,
          ),
      ],
    );
  }

  /// A single-line summary of the current → latest versions.
  String _statusLine(UpdateController c) {
    final current = c.currentVersion?.toString();
    final latest = c.manifestVersionLabel;
    final versions = current != null && latest != null && current != latest
        ? 'NexaDrive v$current \u2192 v$latest'
        : current != null
            ? 'NexaDrive v$current'
            : 'NexaDrive';
    switch (c.status) {
      case UpdateStatus.idle:
        return c.latestKnownLabel != null
            ? 'Latest known version ${c.latestKnownLabel}'
            : 'Not checked yet';
      case UpdateStatus.checking:
        return 'Contacting the release server\u2026';
      case UpdateStatus.downloading:
        return 'Fetching the verified installer\u2026';
      case UpdateStatus.verifying:
        return 'Verifying checksums\u2026';
      case UpdateStatus.upToDate:
        return 'You are on the latest version';
      case UpdateStatus.updateAvailable:
        return latest != null ? 'v$latest is ready for your device' : versions;
      case UpdateStatus.mandatory:
        return latest != null ? 'v$latest is required to continue' : versions;
      case UpdateStatus.completed:
        return 'The update was installed successfully';
      case UpdateStatus.cancelled:
        return 'The download was cancelled';
      case UpdateStatus.failed:
        return c.errorMessage ?? 'The update could not be completed';
      case UpdateStatus.offline:
        return 'No internet connection';
      case UpdateStatus.readyToInstall:
        return 'The verified installer is ready';
      case UpdateStatus.installingHandoff:
        return 'Finish the installation in the system dialog';
      case UpdateStatus.unsupported:
        return c.errorMessage ?? 'Updates are not supported on this platform';
      case UpdateStatus.paused:
        return 'Paused — your progress is kept, resume whenever you like.';
      case UpdateStatus.needsUserAction:
        return 'Android needs permission to install the update';
    }
  }
}

(IconData, String, Color) _statusVisual(UpdateStatus status, Brightness b) {
  final accent = AppColors.accentFor(b);
  final success = AppColors.successFor(b);
  final warning = AppColors.warningFor(b);
  final error = AppColors.errorFor(b);
  // (icon, headline, color)
  return switch (status) {
    UpdateStatus.idle => (Icons.system_update_alt_rounded, 'Not checked yet', accent),
    UpdateStatus.checking => (Icons.cloud_sync_outlined, 'Checking for updates', accent),
    UpdateStatus.upToDate => (Icons.check_circle_rounded, 'Up to date', success),
    UpdateStatus.updateAvailable => (Icons.system_update_alt_rounded, 'Update available', accent),
    UpdateStatus.mandatory => (Icons.error_outline_rounded, 'Mandatory update', warning),
    UpdateStatus.downloading => (Icons.download_rounded, 'Downloading', accent),
    UpdateStatus.paused => (Icons.pause_circle_outline_rounded, 'Download paused', warning),
    UpdateStatus.verifying => (Icons.verified_rounded, 'Verifying download', accent),
    UpdateStatus.readyToInstall => (Icons.inventory_2_outlined, 'Ready to install', accent),
    UpdateStatus.installingHandoff => (Icons.handyman_outlined, 'Continue in the installer', accent),
    UpdateStatus.completed => (Icons.check_circle_rounded, 'Installed', success),
    UpdateStatus.failed => (Icons.error_rounded, 'Update failed', error),
    UpdateStatus.cancelled => (Icons.cancel_outlined, 'Cancelled', warning),
    UpdateStatus.offline => (Icons.cloud_off_rounded, 'Offline', warning),
    UpdateStatus.unsupported => (Icons.priority_high_rounded, 'Unsupported', warning),
    UpdateStatus.needsUserAction => (Icons.lock_outline_rounded, 'Permission needed', warning),
  };
}

/// A quiet progress bar that sits in the Status panel while work is in
/// flight. Downloads show a quantifiable bar + bytes; check/verify phases
/// show a gentle pulse so the surface never looks stuck.
class _ProgressRow extends StatelessWidget {
  final UpdateController controller;
  final Color color;
  final bool inProgress;
  const _ProgressRow({
    required this.controller,
    required this.color,
    required this.inProgress,
  });

  @override
  Widget build(BuildContext context) {
    final received = controller.receivedBytes;
    final total = controller.totalBytes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space16, AppDimens.space4, AppDimens.space16, AppDimens.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: inProgress
                ? TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: 0,
                      end: controller.progress.clamp(0.0, 1.0),
                    ),
                    duration: AppMotion.resolve(context, AppMotion.normal),
                    curve: AppMotion.standard,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      color: color,
                      backgroundColor:
                          color.withValues(alpha: 0.12),
                    ),
                  )
                : LinearProgressIndicator(
                    minHeight: 6,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.12),
                  ),
          ),
          const SizedBox(height: AppDimens.space10),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    inProgress
                        ? '${_bytes(received)}'
                            '${total != null ? ' of ${_bytes(total)} Downloaded' : ' downloaded'}'
                        : controller.status == UpdateStatus.downloading
                            ? 'Almost done\u2026'
                            : 'Checking, this usually takes a moment.',
                    style: AppTextStyle.caption.copyWith(
                      color: AppColors.textSecondaryFor(Theme.of(context).brightness),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (controller.status == UpdateStatus.downloading) ...[
                Text(
                  '${(controller.progress.clamp(0.0, 1.0) * 100).round()}%',
                  style: AppTextStyle.chipLabel.copyWith(
                    color: AppColors.textPrimaryFor(Theme.of(context).brightness),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: controller.cancelDownload,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentFor(Theme.of(context).brightness),
                    minimumSize: const Size(44, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space8,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One primary action that moves the current state forward.
class _ActionArea extends StatelessWidget {
  final UpdateController controller;
  const _ActionArea({required this.controller});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final status = controller.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (status) {
          UpdateStatus.idle =>
            _PrimaryButton(
              onPressed: () => controller.checkForUpdates(manual: true),
              label: 'Check for updates',
            ),
          UpdateStatus.checking ||
          UpdateStatus.verifying ||
          UpdateStatus.downloading =>
            const SizedBox.shrink(),
          UpdateStatus.upToDate =>
            _PrimaryButton(
              onPressed: () => controller.checkForUpdates(manual: true),
              label: 'Check again',
            ),
          UpdateStatus.updateAvailable ||
          UpdateStatus.cancelled =>
            _PrimaryButton(
              onPressed: controller.selectedArtifact == null
                  ? null
                  : controller.download,
              label: 'Download & install',
            ),
          UpdateStatus.mandatory =>
            _PrimaryButton(
              onPressed: controller.selectedArtifact == null
                  ? null
                  : controller.download,
              label: 'Download now',
            ),
          UpdateStatus.readyToInstall =>
            _PrimaryButton(
              onPressed: controller.install,
              label: _installLabel(controller),
            ),
          UpdateStatus.installingHandoff =>
            _PrimaryButton(
              onPressed: controller.reconcileAfterResume,
              label: 'I completed the install',
            ),
          UpdateStatus.completed =>
            _PrimaryButton(
              onPressed: () => controller.checkForUpdates(manual: true),
              label: 'Check again',
            ),
          UpdateStatus.paused =>
            _PrimaryButton(
              onPressed: controller.resume,
              label: 'Resume download',
              icon: Icons.play_arrow_rounded,
            ),
          UpdateStatus.offline ||
          UpdateStatus.unsupported =>
            _ErrorBody(controller: controller),          UpdateStatus.failed => _UpdateFailedBody(controller: controller),
          UpdateStatus.needsUserAction =>
            _InstallBlockedBody(controller: controller),
        },
        if (status == UpdateStatus.upToDate ||
            status == UpdateStatus.idle ||
            status == UpdateStatus.completed ||
            status == UpdateStatus.offline) ...[
          const SizedBox(height: AppDimens.space10),
          Center(
            child: Text(
              controller.latestKnownLabel != null
                  ? 'Last checked: ${controller.lastCheckLabel}'
                  : 'Latest known version is shown automatically.',
              style: AppTextStyle.caption.copyWith(
                color: AppColors.textTertiaryFor(brightness),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _installLabel(UpdateController c) {
    if (c.installerKind == 'apk' || c.installerKind == 'installer') {
      return 'Install now';
    }
    if (c.installerKind == 'appimage') return 'Apply update';
    if (c.installerKind == 'zip' || c.installerKind == 'portable') {
      return 'Update portable app';
    }
    return 'Finish install';
  }
}

class _PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  const _PrimaryButton({
    required this.onPressed,
    required this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppDimens.touchTargetLarge),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
        textStyle: AppTextStyle.button,
      ),
      child: icon != null
      ? FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(AppDimens.touchTargetLarge),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
            textStyle: AppTextStyle.button,
          ),
          icon: Icon(icon, size: AppDimens.iconSmall),
          label: Text(label),
        )
      : FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(AppDimens.touchTargetLarge),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
            textStyle: AppTextStyle.button,
          ),
          child: Text(label),
        ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final UpdateController controller;
  const _ErrorBody({required this.controller});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final message = controller.errorMessage ??
        (controller.status == UpdateStatus.offline
            ? 'No internet connection. Check your network and try again.'
            : 'The update could not be completed.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NoticePanel(
          icon: controller.status == UpdateStatus.unsupported
              ? Icons.priority_high_rounded
              : Icons.info_outline_rounded,
          color: AppColors.warningFor(brightness),
          text: message,
        ),
        const SizedBox(height: AppDimens.space12),
        _PrimaryButton(
          onPressed: () => controller.checkForUpdates(manual: true),
          label: controller.retryable ? 'Try again' : 'Check again',
        ),
      ],
    );
  }
}

class _UpdateFailedBody extends StatelessWidget {
  final UpdateController controller;
  const _UpdateFailedBody({required this.controller});

  @override
  Widget build(BuildContext context) {
    final wasDownloading = controller.selectedArtifact != null &&
        controller.downloadedPath == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NoticePanel(
          icon: Icons.error_outline_rounded,
          color: AppColors.errorFor(Theme.of(context).brightness),
          text: controller.errorMessage ?? 'The update could not be completed.',
        ),
        const SizedBox(height: AppDimens.space12),
        _PrimaryButton(
          onPressed: wasDownloading
              ? controller.retryDownload
              : () => controller.checkForUpdates(manual: true),
          label: wasDownloading ? 'Retry download' : 'Try again',
        ),
      ],
    );
  }
}

/// Android blocked the installer hand-off (missing "install unknown apps"
/// consent). Explain it, deep-link to the exact settings screen, and offer a
/// retry that re-launches the installer once the user returns.
class _InstallBlockedBody extends StatelessWidget {
  final UpdateController controller;
  const _InstallBlockedBody({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NoticePanel(
          icon: Icons.lock_outline_rounded,
          color: AppColors.warningFor(Theme.of(context).brightness),
          text: controller.infoMessage ??
              'Android needs your permission to install this update.',
        ),
        const SizedBox(height: AppDimens.space12),
        _PrimaryButton(
          onPressed: controller.install,
          label: 'Install now',
        ),
        const SizedBox(height: AppDimens.space8),
        OutlinedButton.icon(
          onPressed: controller.requestInstallPermission,
          icon: const Icon(Icons.settings_rounded, size: AppDimens.iconSmall),
          label: const Text('Open install permission settings'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(AppDimens.touchTargetLarge),
          ),
        ),
      ],
    );
  }
}

class _NoticePanel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _NoticePanel({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
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

class _InstallHint extends StatelessWidget {
  final UpdateController controller;
  const _InstallHint({required this.controller});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final platform =
        controller.resolvedPlatform == AppPlatform.linux ? 'Linux' : 'your device';
    final text = controller.infoMessage ??
        'Follow the prompts and come back to NexaDrive when the update is done.';
    return Container(
      padding: const EdgeInsets.all(AppDimens.space16),
      decoration: BoxDecoration(
        color: AppColors.accentSubtleFor(brightness),
        borderRadius: BorderRadius.circular(AppDimens.radiusTile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.handyman_outlined,
                color: AppColors.accentTextFor(brightness),
                size: AppDimens.iconSmall,
              ),
              const SizedBox(width: AppDimens.space8),
              Text(
                'Finish on $platform',
                style: AppTextStyle.chipLabel.copyWith(
                  color: AppColors.accentTextFor(brightness),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space8),
          Text(
            text,
            style: AppTextStyle.rowSubtitle.copyWith(
              color: AppColors.textPrimaryFor(brightness),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DebActions extends StatelessWidget {
  final UpdateController controller;
  const _DebActions({required this.controller});

  @override
  Widget build(BuildContext context) {
    final path = controller.downloadedPath;
    if (path == null) return const SizedBox.shrink();
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NoticePanel(
          icon: Icons.widgets_outlined,
          color: AppColors.infoFor(brightness),
          text:
              'Debian package ready at:\n$path\n\nInstall with:\nsudo dpkg -i $path',
        ),
        const SizedBox(height: AppDimens.space12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: controller.openDebWithSystemInstaller,
                icon: const Icon(Icons.open_in_new_rounded, size: AppDimens.iconSmall),
                label: const Text('Open package'),
              ),
            ),
            const SizedBox(width: AppDimens.space8),
            IconButton(
              tooltip: 'Copy install command',
              onPressed: () => Clipboard.setData(
                ClipboardData(text: 'sudo dpkg -i $path'),
              ),
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailsGroup extends StatelessWidget {
  final UpdateController controller;
  const _DetailsGroup({required this.controller});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final manifest = controller.manifest!;
    final size = controller.selectedArtifact?.size;
    final date = manifest.releaseDate.toLocal();
    final minText = manifest.minimumSupportedVersion?.toString() ?? 'None';

    return OneUiGroupedList(
      header: 'Release details',
      children: [
        OneUiGroupTile(
          icon: Icons.arrow_upward_rounded,
          title: 'Version ${manifest.version}',
          subtitle:
              '${manifest.prerelease ? 'Pre-release' : 'Release'} · Published ${_dateLabel(date)}',
          showChevron: false,
        ),
        OneUiInfoRow(label: 'Current version', value: controller.currentVersion?.toString() ?? '—'),
        OneUiInfoRow(label: 'Latest version', value: manifest.version.toString()),
        OneUiInfoRow(label: 'Released', value: _dateLabel(date)),
        OneUiInfoRow(
          label: 'Size',
          value: size == null ? 'Not published for this device' : _bytes(size),
        ),
        OneUiInfoRow(label: 'Minimum supported', value: minText),
        if (manifest.minimumServerVersion != null) ...[
          OneUiInfoRow(
            label: 'Minimum server version',
            value: manifest.minimumServerVersion!.toString(),
            valueColor: controller.serverIncompatibleWithManifest
                ? AppColors.errorFor(brightness)
                : null,
          ),
          if (controller.serverIncompatibleWithManifest)
            OneUiGroupTile(
              icon: Icons.sync_problem_rounded,
              iconColor: AppColors.errorFor(brightness),
              title: 'Server needs updating',
              subtitle: 'This release needs a newer server. Update your server '
                  'installation before installing this app version.',
              showChevron: false,
            ),
        ],
      ],
    );
  }
}

class _ReleaseNotesGroup extends StatelessWidget {
  final UpdateController controller;
  const _ReleaseNotesGroup({required this.controller});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final sections = controller.manifest!.releaseNotes.sections;
    return OneUiGroupedList(
      header: 'What\u2019s new',
      children: [
        for (final entry in sections.entries)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.space16, AppDimens.space12, AppDimens.space16, AppDimens.space6,
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
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.space16, AppDimens.space4, AppDimens.space16, AppDimens.space4,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6.5),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accentFor(brightness).withValues(alpha: 0.55),
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
              const SizedBox(height: AppDimens.space4),
            ],
          ),
      ],
    );
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

String _dateLabel(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_ReleaseNotesGroup._monthNames[local.month - 1]} ${local.year}';
}

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}