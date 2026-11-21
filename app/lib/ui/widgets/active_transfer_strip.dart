import 'package:flutter/material.dart';

import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';
import '../../services/upload_item.dart';
import '../../services/upload_manager.dart';
import 'nexa_progress.dart';
import 'nexa_surface.dart';

/// Compact live status for the upload queue.
///
/// The strip floats immediately above the navigation pill so transfer progress
/// stays visible from every tab. It reads the single queue through
/// [UploadManager]; the shell owns navigation and toast feedback, while this
/// widget owns only the persistent controls.
class ActiveTransferStrip extends StatefulWidget {
  final UploadManager manager;
  final VoidCallback onOpen;
  final VoidCallback onPauseAll;
  final VoidCallback onResumeAll;
  final VoidCallback onRetryFailed;
  final VoidCallback onCancelAll;

  const ActiveTransferStrip({
    super.key,
    required this.manager,
    required this.onOpen,
    required this.onPauseAll,
    required this.onResumeAll,
    required this.onRetryFailed,
    required this.onCancelAll,
  });

  @override
  State<ActiveTransferStrip> createState() => _ActiveTransferStripState();
}

class _ActiveTransferStripState extends State<ActiveTransferStrip> {
  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.manager.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = widget.manager.items();
    final active = items
        .where(
          (item) =>
              item.state == UploadState.queued ||
              item.state == UploadState.uploading ||
              item.state == UploadState.retrying,
        )
        .toList(growable: false);
    final paused = items
        .where((item) => item.state == UploadState.paused)
        .toList(growable: false);
    final failed = items
        .where((item) => item.state == UploadState.failed)
        .toList(growable: false);
    final totalBytes = items.fold<int>(0, (sum, item) => sum + item.size);
    final transferredBytes = items.fold<int>(
      0,
      (sum, item) => sum + item.transferred,
    );
    final progress = totalBytes == 0
        ? null
        : (transferredBytes / totalBytes).clamp(0.0, 1.0).toDouble();

    final title = _title(active.length, paused.length, failed.length);
    final subtitle = _subtitle(active, paused, failed, progress);
    final needsAttention = failed.isNotEmpty;

    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, AppMotion.fast),
      switchInCurve: AppMotion.curveFor(context, AppMotion.standard),
      switchOutCurve: AppMotion.curveFor(context, AppMotion.standard),
      child: NexaSurface(
        key: ValueKey('$title|$subtitle'),
        level: NexaSurfaceLevel.floating,
        radius: AppDimens.radiusPill,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppDimens.transferStripHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space12,
              vertical: AppDimens.space6,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: '$title. $subtitle',
                    hint: 'Opens transfers',
                    child: InkWell(
                      onTap: widget.onOpen,
                      borderRadius: BorderRadius.circular(
                        AppDimens.radiusPill,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppDimens.space2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeSemantics(
                              child: SizedBox(
                                width: AppDimens.iconMedium,
                                height: AppDimens.iconMedium,
                                child: needsAttention
                                    ? Icon(
                                        Icons.error_outline_rounded,
                                        size: AppDimens.iconMedium,
                                        color: scheme.error,
                                      )
                                    : NexaCircularProgress(
                                        value: active.isEmpty ? 1 : progress,
                                        size: AppDimens.iconMedium,
                                        color: active.isEmpty
                                            ? scheme.onSurfaceVariant
                                            : scheme.primary,
                                      ),
                              ),
                            ),
                            const SizedBox(width: AppDimens.space12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyle.titleSmall.copyWith(
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: AppDimens.space2),
                                  Text(
                                    subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyle.bodySmall.copyWith(
                                      color: needsAttention
                                          ? scheme.error
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (failed.isNotEmpty)
                  _stripAction(
                    tooltip: 'Retry failed uploads',
                    icon: Icons.refresh_rounded,
                    onPressed: widget.onRetryFailed,
                  ),
                if (paused.isNotEmpty && active.isEmpty)
                  _stripAction(
                    tooltip: 'Resume uploads',
                    icon: Icons.play_arrow_rounded,
                    onPressed: widget.onResumeAll,
                  ),
                if (active.isNotEmpty)
                  _stripAction(
                    tooltip: 'Pause uploads',
                    icon: Icons.pause_rounded,
                    onPressed: widget.onPauseAll,
                  ),
                _stripAction(
                  tooltip: 'Cancel uploads',
                  icon: Icons.close_rounded,
                  onPressed: widget.onCancelAll,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stripAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: AppDimens.iconSmall),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      constraints: const BoxConstraints(
        minWidth: AppDimens.touchTarget,
        minHeight: AppDimens.touchTarget,
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  String _title(int active, int paused, int failed) {
    if (failed > 0 && active == 0 && paused == 0) {
      return failed == 1
          ? '1 upload needs attention'
          : '$failed uploads need attention';
    }
    if (failed > 0) {
      return failed == 1 ? '1 upload failed' : '$failed uploads failed';
    }
    if (paused > 0 && active == 0) {
      return paused == 1 ? 'Upload paused' : 'Uploads paused';
    }
    return active == 1 ? 'Uploading 1 file' : 'Uploading $active files';
  }

  String _subtitle(
    List<UploadItem> active,
    List<UploadItem> paused,
    List<UploadItem> failed,
    double? progress,
  ) {
    final failedLabel =
        failed.length == 1 ? '1 failed' : '${failed.length} failed';
    if (failed.isNotEmpty && active.isEmpty && paused.isEmpty) {
      return 'Tap to review what failed';
    }
    if (failed.isNotEmpty && active.isNotEmpty && progress != null) {
      return '$failedLabel · ${(progress * 100).round()}% complete';
    }
    if (failed.isNotEmpty) {
      return '$failedLabel · Tap for details';
    }
    if (active.isNotEmpty && progress != null) {
      return '${(progress * 100).round()}% complete · Tap for details';
    }
    return 'Waiting to start · Tap for details';
  }
}
