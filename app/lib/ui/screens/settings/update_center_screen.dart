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
              _StatusPanel(controller: controller),
              const SizedBox(height: AppDimens.space20),
              _ActionArea(controller: controller),
              if (controller.hasUpdate && controller.selectedArtifact == null) ...[
                const SizedBox(height: AppDimens.space16),
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
                  (controller.installationKind ==
                          null ||
                      controller.installationKind ==
                          InstallationKind.unknown) &&
                  controller.selectedArtifact == null) ...[
                const SizedBox(height: AppDimens.space16),
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
                const SizedBox(height: AppDimens.space16),
                _InstallHint(controller: controller),
              ],
              if (status == UpdateStatus.readyToInstall &&
                  controller.installerKind == 'deb') ...[
                const SizedBox(height: AppDimens.space16),
                _DebActions(controller: controller),
              ],
              if (controller.manifest != null) ...[
                const SizedBox(height: AppDimens.space28),
                _DetailsGroup(controller: controller),
              ],
              if (controller.manifest != null &&
                  !controller.manifest!.releaseNotes.isEmpty) ...[
                const SizedBox(height: AppDimens.space28),
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

class _StatusPanel extends StatelessWidget {
  final UpdateController controller;
  const _StatusPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final status = controller.status;
    final (icon, label, color) = _statusVisual(status, brightness);

    final containerColor = switch (status) {
      UpdateStatus.completed => AppColors.successContainerFor(brightness),
      UpdateStatus.failed ||
      UpdateStatus.cancelled =>
        AppColors.errorContainerFor(brightness),
      UpdateStatus.offline ||
      UpdateStatus.unsupported ||
      UpdateStatus.needsUserAction =>
        AppColors.warningContainerFor(brightness),
      UpdateStatus.mandatory => AppColors.warningContainerFor(brightness),
      _ => AppColors.accentContainerFor(brightness),
    };
    final onContainer = switch (status) {
      UpdateStatus.completed => AppColors.onSuccessContainerFor(brightness),
      UpdateStatus.failed ||
      UpdateStatus.cancelled =>
        AppColors.onErrorContainerFor(brightness),
      UpdateStatus.offline ||
      UpdateStatus.unsupported ||
      UpdateStatus.needsUserAction =>
        AppColors.onWarningContainerFor(brightness),
      UpdateStatus.mandatory => AppColors.onWarningContainerFor(brightness),
      _ => AppColors.onAccentContainerFor(brightness),
    };

    final current = controller.currentVersion?.toString() ?? '—';
    final latest = controller.manifestVersionLabel ?? '—';

    return Semantics(
      container: true,
      label: '$label. Current version $current. Latest version $latest.',
      child: AnimatedContainer(
        duration: AppMotion.resolve(context, AppMotion.fast),
        curve: AppMotion.standard,
        padding: const EdgeInsets.all(AppDimens.space16),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedSwitcher(
                  duration: AppMotion.resolve(context, AppMotion.fast),
                  child: Icon(
                    icon,
                    key: ValueKey(icon),
                    color: color,
                    size: AppDimens.iconMedium,
                  ),
                ),
                const SizedBox(width: AppDimens.space8),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyle.sectionHeader.copyWith(
                      color: onContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _VersionChip(label: 'Current', value: current, color: onContainer),
                const SizedBox(width: AppDimens.space8),
                _VersionChip(label: 'Latest', value: latest, color: onContainer),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (IconData, String, Color) _statusVisual(UpdateStatus status, Brightness b) {
    final accent = AppColors.accentFor(b);
    final success = AppColors.successFor(b);
    final warning = AppColors.warningFor(b);
    final error = AppColors.errorFor(b);
    switch (status) {
      case UpdateStatus.idle:
        return (Icons.system_update_alt_rounded, 'Not checked yet', accent);
      case UpdateStatus.checking:
        return (Icons.cloud_sync_outlined, 'Checking for updates…', accent);
      case UpdateStatus.upToDate:
        return (Icons.check_circle_outline_rounded, 'Up to date', success);
      case UpdateStatus.updateAvailable:
        return (Icons.system_update_alt_rounded, 'Update available', accent);
      case UpdateStatus.mandatory:
        return (Icons.error_outline_rounded, 'Mandatory update', warning);
      case UpdateStatus.downloading:
        return (Icons.download_rounded, 'Downloading', accent);
      case UpdateStatus.verifying:
        return (Icons.verified_rounded, 'Verifying download', accent);
      case UpdateStatus.readyToInstall:
        return (Icons.inventory_2_outlined, 'Ready to install', accent);
      case UpdateStatus.installingHandoff:
        return (Icons.handyman_outlined, 'Continue in the installer', accent);
      case UpdateStatus.completed:
        return (Icons.check_circle_rounded, 'Installed', success);
      case UpdateStatus.failed:
        return (Icons.error_rounded, 'Update failed', error);
      case UpdateStatus.cancelled:
        return (Icons.cancel_outlined, 'Cancelled', warning);
      case UpdateStatus.offline:
        return (Icons.cloud_off_rounded, 'Offline', warning);
      case UpdateStatus.unsupported:
        return (Icons.priority_high_rounded, 'Unsupported', warning);
      case UpdateStatus.needsUserAction:
        return (Icons.lock_outline_rounded, 'Permission needed', warning);
    }
  }
}

class _VersionChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _VersionChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12, vertical: AppDimens.space6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Text(
        '$label  $value',
        style: AppTextStyle.chipLabel.copyWith(color: color),
      ),
    );
  }
}

class _ActionArea extends StatelessWidget {
  final UpdateController controller;
  const _ActionArea({required this.controller});

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (status) {
          UpdateStatus.idle =>
            _PrimaryButton(onPressed: () => controller.checkForUpdates(manual: true), label: 'Check for updates'),
          UpdateStatus.checking ||
          UpdateStatus.verifying ||
          UpdateStatus.downloading =>
            _DownloadProgress(controller: controller, cancellable: status == UpdateStatus.downloading),
          UpdateStatus.upToDate =>
            _PrimaryButton(onPressed: () => controller.checkForUpdates(manual: true), label: 'Check again'),
          UpdateStatus.updateAvailable ||
          UpdateStatus.cancelled =>
            _PrimaryButton(onPressed: controller.selectedArtifact == null ? null : () => controller.download(), label: 'Download & install'),
          UpdateStatus.mandatory =>
            _PrimaryButton(onPressed: controller.selectedArtifact == null ? null : () => controller.download(), label: 'Download now'),
          UpdateStatus.readyToInstall =>
            _PrimaryButton(onPressed: () => controller.install(), label: _installLabel(controller)),
          UpdateStatus.installingHandoff =>
            _PrimaryButton(onPressed: () => controller.reconcileAfterResume(), label: 'I completed the install'),
          UpdateStatus.completed =>
            _PrimaryButton(onPressed: () => controller.checkForUpdates(manual: true), label: 'Check again'),
          UpdateStatus.offline ||
          UpdateStatus.unsupported =>
            _ErrorBody(controller: controller),
          UpdateStatus.failed => _UpdateFailedBody(controller: controller),
          UpdateStatus.needsUserAction =>
            _InstallBlockedBody(controller: controller),
        },
        if (status == UpdateStatus.upToDate ||
            status == UpdateStatus.idle ||
            status == UpdateStatus.completed ||
            status == UpdateStatus.offline) ...[
          const SizedBox(height: AppDimens.space8),
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
  const _PrimaryButton({required this.onPressed, required this.label});

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
      child: Text(label),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  final UpdateController controller;
  final bool cancellable;
  const _DownloadProgress({required this.controller, required this.cancellable});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final progress = controller.progress.clamp(0.0, 1.0);
    final received = controller.receivedBytes;
    final total = controller.totalBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          label:
              'Downloading ${_bytes(received)} of ${total == null ? 'unknown size' : _bytes(total)}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: AppColors.accentFor(brightness),
              backgroundColor: AppColors.dividerFor(brightness),
            ),
          ),
        ),
        const SizedBox(height: AppDimens.space10),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_bytes(received)}${total != null ? ' / ${_bytes(total)}' : ''}',
                style: AppTextStyle.caption.copyWith(
                  color: AppColors.textSecondaryFor(brightness),
                ),
              ),
            ),
            if (cancellable)
              TextButton(
                onPressed: controller.cancelDownload,
                child: const Text('Cancel'),
              ),
          ],
        ),
      ],
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
              ? () => controller.retryDownload()
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
          onPressed: () => controller.install(),
          label: 'Install now',
        ),
        const SizedBox(height: AppDimens.space8),
        OutlinedButton.icon(
          onPressed: () => controller.requestInstallPermission(),
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
                onPressed: () => controller.openDebWithSystemInstaller(),
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
            Container(
              margin: const EdgeInsets.fromLTRB(
                AppDimens.space16,
                AppDimens.space16,
                AppDimens.space16,
                AppDimens.space8,
              ),
              padding: const EdgeInsets.all(AppDimens.space12),
              decoration: BoxDecoration(
                color: AppColors.errorFor(brightness).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppDimens.radiusInner),
              ),
              child: Text(
                'This release needs a newer server. Update your server '
                'installation before installing this app version.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.errorFor(brightness),
                    ),
              ),
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
                    AppDimens.space16, AppDimens.space2, AppDimens.space16, AppDimens.space2,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.textTertiaryFor(brightness),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDimens.space10),
                      Expanded(
                        child: Text(
                          item,
                          style: AppTextStyle.rowSubtitle.copyWith(
                            color: AppColors.textPrimaryFor(brightness),
                            height: 1.4,
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