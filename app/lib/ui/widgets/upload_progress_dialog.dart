import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_typography.dart';
import '../../core/utils/format.dart';
import '../../services/api.dart';
import '../../services/upload_item.dart';
import '../../services/upload_manager.dart';

/// One UI upload progress dialog — modal while active, showing per-file
/// progress, then a summary with retry for failures.
///
/// The dialog is a *view* of the queue, not the queue itself. Closing it does
/// not stop a transfer: the upload keeps running and stays visible on the
/// Transfers screen.
class UploadProgressDialog extends StatefulWidget {
  final UploadManager manager;
  final List<String> uploadIds;
  final String destination;

  const UploadProgressDialog({
    super.key,
    required this.manager,
    required this.uploadIds,
    required this.destination,
  });

  /// Queues [files] and shows the progress dialog.
  static Future<void> show(
    BuildContext context, {
    required List<PlatformFile> files,
    required String folder,
  }) async {
    final sources = <UploadSource>[];
    for (final file in files) {
      final path = file.path;
      if (path == null) continue;
      sources.add(UploadSource(
        path: path,
        name: file.name,
        size: file.lengthSync() ?? 0,
      ));
    }
    await showSources(context, sources: sources, folder: folder);
  }

  /// Queues [sources] and shows the progress dialog.
  static Future<void> showSources(
    BuildContext context, {
    required List<UploadSource> sources,
    required String folder,
    Api? api,
  }) async {
    if (sources.isEmpty) return;
    final manager = UploadManager.current;
    if (api != null) manager.attach(api);
    final ids = await manager.enqueueAll(sources, folder);
    if (!context.mounted) return;
    if (ids.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => UploadProgressDialog(
        manager: manager,
        uploadIds: ids,
        destination: folder,
      ),
    );
  }

  /// Path-based variant used by tests and headless flows: uploads the files at
  /// [paths] without going through a platform file picker.
  static Future<void> showPaths(
    BuildContext context, {
    required Api api,
    required List<String> paths,
    required String folder,
  }) async {
    final sources = <UploadSource>[];
    for (final path in paths) {
      final file = File(path);
      final size = await file.exists() ? await file.length() : 0;
      sources.add(UploadSource(
        path: path,
        name: file.uri.pathSegments.last,
        size: size,
      ));
    }
    if (!context.mounted) return;
    await showSources(context, sources: sources, folder: folder, api: api);
  }

  @override
  State<UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<UploadProgressDialog> {
  /// The items of this batch, in queue order.
  List<UploadItem> _items = [];

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.manager.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final byId = <String, UploadItem>{
      for (final item in widget.manager.items()) item.id: item,
    };
    final items = <UploadItem>[];
    for (final id in widget.uploadIds) {
      final item = byId[id];
      if (item != null) items.add(item);
    }
    setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final secondary = AppColors.textSecondaryFor(brightness);
    final total = _items.fold<int>(0, (int sum, UploadItem item) => sum + item.size);
    final done = _items.fold<int>(
        0, (int sum, UploadItem item) => sum + item.transferred);
    final completed =
        _items.where((UploadItem item) => item.state == UploadState.completed).length;
    final failed =
        _items.where((UploadItem item) => item.state == UploadState.failed).length;
    final active = _items
        .where((UploadItem item) =>
            item.state == UploadState.uploading ||
            item.state == UploadState.retrying ||
            item.state == UploadState.queued)
        .length;
    final paused = _items
        .where((UploadItem item) => item.state == UploadState.paused)
        .length;
    final isActive = active > 0;
    final progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final allSucceeded =
        _items.isNotEmpty && completed == _items.length && failed == 0;

    final Widget statusIcon;
    final String statusTitle;
    if (isActive) {
      statusIcon = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
      statusTitle = 'Uploading…';
    } else if (allSucceeded) {
      statusIcon =
          Icon(Icons.check_circle_rounded, color: successFor(brightness));
      statusTitle = 'Upload complete';
    } else if (_items.isEmpty) {
      statusIcon = Icon(
        Icons.error_outline_rounded,
        color: brightness == Brightness.dark
            ? AppColors.errorDark
            : AppColors.errorLight,
      );
      statusTitle = 'Nothing was uploaded';
    } else {
      statusIcon = Icon(
        Icons.error_outline_rounded,
        color: brightness == Brightness.dark
            ? AppColors.errorDark
            : AppColors.errorLight,
      );
      statusTitle = 'Upload finished with issues';
    }

    return AlertDialog(
      title: Row(
        children: [
          AnimatedSwitcher(
            duration: AppMotion.fast,
            child: SizedBox(key: ValueKey(statusTitle), child: statusIcon),
          ),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Text(
              statusTitle,
              style: AppTextStyle.dialogTitle.copyWith(
                color: AppColors.textPrimaryFor(brightness),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${Format.count(completed, 'file')} uploaded to '
              '${widget.destination.isEmpty ? 'My files' : widget.destination}',
              style: AppTextStyle.caption.copyWith(color: secondary),
            ),
            const SizedBox(height: AppDimens.space12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
            const SizedBox(height: AppDimens.space6),
            Text(
              '${Format.bytes(done)} of ${Format.bytes(total)}'
              '${paused > 0 ? ' · $paused paused' : ''}',
              style: AppTextStyle.micro.copyWith(color: secondary),
            ),
            const SizedBox(height: AppDimens.space12),
            if (_items.isEmpty)
              Text(
                'No files could be started.',
                style: AppTextStyle.caption.copyWith(color: secondary),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppDimens.space2),
                  itemBuilder: (_, int index) =>
                      _buildRow(context, _items[index]),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (isActive)
          TextButton(onPressed: _pauseAll, child: const Text('Pause all')),
        if (paused > 0)
          TextButton(onPressed: _resumeAll, child: const Text('Resume all')),
        if (failed > 0)
          TextButton(
            onPressed: _retryFailed,
            child: const Text('Retry failed'),
          ),
        if (isActive)
          TextButton(onPressed: _cancelAll, child: const Text('Cancel'))
        else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(failed > 0 ? 'Close' : 'Done'),
          ),
      ],
    );
  }

  Future<void> _pauseAll() async {
    for (final item in _items) {
      if (item.state == UploadState.queued ||
          item.state == UploadState.uploading ||
          item.state == UploadState.retrying) {
        await widget.manager.pause(item.id);
      }
    }
    _refresh();
  }

  Future<void> _resumeAll() async {
    for (final item in _items) {
      if (item.state == UploadState.paused) {
        await widget.manager.resume(item.id);
      }
    }
    _refresh();
  }

  Future<void> _cancelAll() async {
    for (final item in _items) {
      if (!item.state.isTerminal) {
        await widget.manager.cancel(item.id);
      }
    }
    _refresh();
  }

  Future<void> _retryFailed() async {
    await widget.manager.retryFailed();
    _refresh();
  }

  Color successFor(Brightness b) =>
      b == Brightness.dark ? AppColors.successDark : AppColors.successLight;

  Widget _buildRow(BuildContext context, UploadItem item) {
    final brightness = Theme.of(context).brightness;
    final state = item.state;
    final failed = state == UploadState.failed;
    final doneStatus = state == UploadState.completed;
    final uploading = state == UploadState.uploading;
    final paused = state == UploadState.paused;
    final cancelled = state == UploadState.cancelled;
    final frac = item.progress;

    final IconData icon;
    final Color color;
    final String label;
    if (doneStatus) {
      icon = Icons.check_circle_outline_rounded;
      color = successFor(brightness);
      label = 'Uploaded';
    } else if (failed) {
      icon = Icons.error_outline_rounded;
      color = brightness == Brightness.dark
          ? AppColors.errorDark
          : AppColors.errorLight;
      label = item.error ?? 'Failed';
    } else if (cancelled) {
      icon = Icons.cancel_outlined;
      color = secondaryFor(brightness);
      label = 'Cancelled';
    } else if (paused) {
      icon = Icons.pause_circle_outline_rounded;
      color = secondaryFor(brightness);
      label = 'Paused';
    } else if (uploading) {
      icon = Icons.cloud_upload_outlined;
      color = AppColors.accentFor(brightness);
      label = '${Format.bytes(item.transferred)} / ${Format.bytes(item.size)}';
    } else if (state == UploadState.retrying) {
      icon = Icons.refresh_rounded;
      color = AppColors.accentFor(brightness);
      label = 'Retrying…';
    } else {
      icon = Icons.schedule_rounded;
      color = secondaryFor(brightness);
      label = 'Waiting…';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space4),
      child: Row(
        children: [
          Icon(icon, size: AppDimens.iconSmall, color: color),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption.copyWith(
                    color: AppColors.textPrimaryFor(brightness),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                if (!doneStatus && !failed)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                    child: LinearProgressIndicator(value: frac, minHeight: 4),
                  ),
                if (!doneStatus) ...[
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.micro.copyWith(
                      color: failed
                          ? (brightness == Brightness.dark
                              ? AppColors.errorDark
                              : AppColors.errorLight)
                          : secondaryFor(brightness),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _rowAction(item),
        ],
      ),
    );
  }

  /// The per-row control: pause, resume, retry or cancel.
  Widget _rowAction(UploadItem item) {
    final brightness = Theme.of(context).brightness;
    final state = item.state;
    if (state == UploadState.completed) {
      return IconButton(
        tooltip: 'Remove from list',
        onPressed: () async {
          await widget.manager.remove(item.id);
          _refresh();
        },
        icon: const Icon(Icons.close_rounded, size: AppDimens.iconSmall),
      );
    }
    if (state == UploadState.failed || state == UploadState.cancelled) {
      return IconButton(
        tooltip: 'Retry',
        onPressed: () async {
          await widget.manager.retry(item.id);
          _refresh();
        },
        icon: const Icon(Icons.refresh_rounded, size: AppDimens.iconSmall),
        color: brightness == Brightness.dark
            ? AppColors.errorDark
            : AppColors.errorLight,
      );
    }
    if (state == UploadState.paused) {
      return IconButton(
        tooltip: 'Resume',
        onPressed: () async {
          await widget.manager.resume(item.id);
          _refresh();
        },
        icon: const Icon(Icons.play_arrow_rounded, size: AppDimens.iconSmall),
      );
    }
    return IconButton(
      tooltip: 'Pause',
      onPressed: () async {
        await widget.manager.pause(item.id);
        _refresh();
      },
      icon: const Icon(Icons.pause_rounded, size: AppDimens.iconSmall),
    );
  }

  Color secondaryFor(Brightness b) => AppColors.textSecondaryFor(b);
}
