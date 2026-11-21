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

/// Material 3 upload progress dialog — an explicit queue view for headless and
/// integration flows, showing per-file progress and retry for failures.
///
/// Normal uploads use [UploadProgressDialog.showSources], which only enqueues:
/// the shell's transfer strip is the persistent progress surface. This widget
/// remains a public view of the queue, but auto-closes shortly after its batch
/// is terminal so it can never be left behind as a modal.
class _TransferMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _TransferMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space10,
          vertical: AppDimens.space8,
        ),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: scheme.brightness == Brightness.dark ? 0.16 : 0.09,
          ),
          borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyle.labelMedium.copyWith(color: color),
            ),
            const SizedBox(height: AppDimens.space2),
            Text(
              value,
              style: AppTextStyle.titleMedium.copyWith(color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

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

  /// Queues [files] without opening a modal. Progress lives in the shell strip.
  static Future<void> show(
    BuildContext context, {
    required List<PlatformFile> files,
    required String folder,
  }) async {
    final sources = <UploadSource>[];
    for (final file in files) {
      final path = file.path;
      final uri = file.uri;
      sources.add(UploadSource(
        // The picker reports metadata without opening the file. A provider
        // URI is retained by file_picker as identifier on Android; paths are
        // used directly on native file-backed selections.
        path: path ?? uri.toString(),
        sourceUri: path == null ? uri.toString() : null,
        name: file.name,
        size: file.lengthSync() ?? 0,
      ));
    }
    await showSources(context, sources: sources, folder: folder);
  }

  /// Queues [sources] without opening a modal.
  ///
  /// The shell observes the same queue and owns all completion feedback, so a
  /// second progress surface here would only cover the navigation pill.
  static Future<void> showSources(
    BuildContext context, {
    required List<UploadSource> sources,
    required String folder,
    Api? api,
  }) async {
    await _enqueue(sources: sources, folder: folder, api: api);
  }

  /// Enqueue helper shared by the normal picker flow and the explicit dialog
  /// entry point used by integration tests.
  static Future<List<String>> _enqueue({
    required List<UploadSource> sources,
    required String folder,
    Api? api,
  }) async {
    if (sources.isEmpty) return const <String>[];
    final manager = UploadManager.current;
    if (api != null) manager.attach(api);
    // Yield once so the selection screen can paint before the journal batch
    // and queue notifications are processed.
    await Future<void>.delayed(Duration.zero);
    final ids = await manager.enqueueAll(sources, folder);
    return ids;
  }

  /// Path-based variant used by tests and headless flows: uploads the files at
  /// [paths] without going through a platform file picker, then shows the
  /// explicit progress view. The dialog auto-closes once the batch is terminal.
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
    final ids = await _enqueue(
      sources: sources,
      folder: folder,
      api: api,
    );
    if (!context.mounted || ids.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => UploadProgressDialog(
        manager: UploadManager.current,
        uploadIds: ids,
        destination: folder,
      ),
    );
  }

  @override
  State<UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<UploadProgressDialog> {
  /// The items of this batch, in queue order.
  List<UploadItem> _items = [];
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
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
    _scheduleAutoClose();
  }

  /// Terminal items can be pruned, so a missing id is treated as finished.
  bool _allTerminal() {
    final byId = <String, UploadItem>{
      for (final item in widget.manager.items()) item.id: item,
    };
    return widget.uploadIds.every(
      (id) => byId[id]?.state.isTerminal ?? true,
    );
  }

  void _scheduleAutoClose() {
    if (_autoCloseTimer != null || !_allTerminal()) return;
    // Enough time to read the final summary, then the route goes away.
    _autoCloseTimer = Timer(AppMotion.ambient * 2, _closeIfActive);
  }

  void _closeIfActive() {
    if (!mounted || !context.mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    // Remove this dialog's own route. A plain pop could dismiss a newer page
    // that was pushed on top while the batch was finishing.
    Navigator.of(context).removeRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = scheme.brightness;
    final secondary = scheme.onSurfaceVariant;
    final total =
        _items.fold<int>(0, (int sum, UploadItem item) => sum + item.size);
    final done = _items.fold<int>(
        0, (int sum, UploadItem item) => sum + item.transferred);
    final completed = _items
        .where((UploadItem item) => item.state == UploadState.completed)
        .length;
    final failed = _items
        .where((UploadItem item) => item.state == UploadState.failed)
        .length;
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
      statusIcon = SizedBox(
        width: AppDimens.iconSmall,
        height: AppDimens.iconSmall,
        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
      );
      statusTitle = 'Uploading…';
    } else if (allSucceeded) {
      statusIcon =
          Icon(Icons.check_circle_rounded, color: successFor(brightness));
      statusTitle = 'Upload complete';
    } else if (_items.isEmpty) {
      statusIcon = Icon(Icons.error_outline_rounded, color: scheme.error);
      statusTitle = 'Nothing was uploaded';
    } else {
      statusIcon = Icon(Icons.error_outline_rounded, color: scheme.error);
      statusTitle = 'Upload finished with issues';
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusDialog),
      ),
      title: Row(
        children: [
          AnimatedSwitcher(
            duration: AppMotion.resolve(context, AppMotion.fast),
            child: SizedBox(key: ValueKey(statusTitle), child: statusIcon),
          ),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Text(
              statusTitle,
              style: AppTextStyle.titleMedium.copyWith(color: scheme.onSurface),
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
              style: AppTextStyle.bodySmall.copyWith(color: secondary),
            ),
            const SizedBox(height: AppDimens.space12),
            Row(
              children: [
                _TransferMetric(
                  label: 'DONE',
                  value: completed.toString(),
                  color: successFor(brightness),
                ),
                const SizedBox(width: AppDimens.space8),
                _TransferMetric(
                  label: 'ACTIVE',
                  value: active.toString(),
                  color: scheme.primary,
                ),
                const SizedBox(width: AppDimens.space8),
                _TransferMetric(
                  label: 'ISSUES',
                  value: failed.toString(),
                  color: scheme.error,
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space12),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: AppMotion.resolve(context, AppMotion.normal),
              curve: AppMotion.standardCurve,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: AppDimens.space8,
                  color: scheme.primary,
                  backgroundColor: scheme.primaryContainer,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.space6),
            Text(
              '${Format.bytes(done)} of ${Format.bytes(total)}'
              '${paused > 0 ? ' · $paused paused' : ''}',
              style: AppTextStyle.labelSmall.copyWith(color: secondary),
            ),
            const SizedBox(height: AppDimens.space12),
            if (_items.isEmpty)
              Text(
                'No files could be started.',
                style: AppTextStyle.bodySmall.copyWith(color: secondary),
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
    final scheme = Theme.of(context).colorScheme;
    final brightness = scheme.brightness;
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
      color = scheme.error;
      label = item.error ?? 'Failed';
    } else if (cancelled) {
      icon = Icons.cancel_outlined;
      color = scheme.onSurfaceVariant;
      label = 'Cancelled';
    } else if (paused) {
      icon = Icons.pause_circle_outline_rounded;
      color = scheme.onSurfaceVariant;
      label = 'Paused';
    } else if (uploading) {
      icon = Icons.cloud_upload_outlined;
      color = scheme.primary;
      label = '${Format.bytes(item.transferred)} / ${Format.bytes(item.size)}';
    } else if (state == UploadState.retrying) {
      icon = Icons.refresh_rounded;
      color = scheme.primary;
      label = 'Retrying…';
    } else {
      icon = Icons.schedule_rounded;
      color = scheme.onSurfaceVariant;
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
                  style: AppTextStyle.labelMedium.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                if (!doneStatus && !failed)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: AppDimens.space4,
                    ),
                  ),
                if (!doneStatus) ...[
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.bodySmall.copyWith(
                      color: failed ? scheme.error : scheme.onSurfaceVariant,
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
    final scheme = Theme.of(context).colorScheme;
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
        color: scheme.error,
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

  Color secondaryFor(Brightness b) => AppColors.scheme(b).onSurfaceVariant;
}
