import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/utils/format.dart';
import '../../services/api.dart';
import '../../services/transfer_queue.dart';

/// One UI upload progress dialog — modal while active, showing per-file
/// progress, then a summary with retry for failures.
class UploadProgressDialog extends StatefulWidget {
  final TransferQueue queue;
  final List<String> uploadIds;
  final String folder;

  const UploadProgressDialog({
    super.key,
    required this.queue,
    required this.uploadIds,
    required this.folder,
  });

  static Future<void> show(
    BuildContext context, {
    required Api api,
    required List<PlatformFile> files,
    required String folder,
  }) async {
    final queue = TransferQueue(api);
    final uploadIds = <String>[];
    try {
      for (final file in files) {
        final item = await queue.enqueue(file, folder);
        uploadIds.add(item.id);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed to start: $e')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UploadProgressDialog(
        queue: queue,
        uploadIds: uploadIds,
        folder: folder,
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
    final queue = TransferQueue(api);
    final uploadIds = <String>[];
    try {
      for (final path in paths) {
        final file = File(path);
        final item = await queue.enqueueLocalPath(
          path,
          name: file.uri.pathSegments.last,
          folder: folder,
        );
        uploadIds.add(item.id);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed to start: $e')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UploadProgressDialog(
        queue: queue,
        uploadIds: uploadIds,
        folder: folder,
      ),
    );
  }

  @override
  State<UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<UploadProgressDialog> {
  List<TransferItem> _items = [];
  Timer? _poll;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _startProcessing();
    _poll = Timer.periodic(const Duration(milliseconds: 700), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  bool _isDone(List<TransferItem> items) => items.every(
        (e) => e.status == 'completed' || (e.status == 'queued' && e.error != null),
      );

  Future<void> _startProcessing() async {
    await widget.queue.process(onChanged: (_) => _refresh());
    if (!mounted) return;
    await _refresh();
    if (mounted && _finished) _poll?.cancel();
  }

  Future<void> _refresh() async {
    final all = await widget.queue.items();
    if (!mounted) return;
    setState(() {
      _items = all.where((e) => widget.uploadIds.contains(e.id)).toList();
      if (_isDone(_items)) {
        _finished = true;
        _poll?.cancel();
      }
    });
  }

  Future<void> _cancel() async {
    final all = await widget.queue.items();
    for (final e in all) {
      if (!widget.uploadIds.contains(e.id)) continue;
      if (e.status != 'completed') await widget.queue.remove(e.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _retry(TransferItem item) async {
    await widget.queue.reset(item.id);
    await _refresh();
    await _startProcessing();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final secondary = AppColors.textSecondaryFor(brightness);
    final total = _items.fold<int>(0, (sum, e) => sum + e.size);
    final done = _items.fold<int>(0, (sum, e) => sum + e.transferred);
    final completed = _items.where((e) => e.status == 'completed').length;
    final failed = _items.where((e) => e.status == 'queued' && e.error != null).length;
    final active = _items.where(
      (e) => e.status != 'completed' && !(e.status == 'queued' && e.error != null),
    ).length;
    final isActive = !_finished && active > 0;
    final progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final allSucceeded = _items.isNotEmpty && _items.every((e) => e.status == 'completed');

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
      statusIcon = Icon(Icons.check_circle_rounded, color: successFor(brightness));
      statusTitle = 'Upload complete';
    } else {
      statusIcon = Icon(
        Icons.error_outline_rounded,
        color: brightness == Brightness.dark ? AppColors.errorDark : AppColors.errorLight,
      );
      statusTitle = 'Upload finished with issues';
    }

    return PopScope(
      canPop: !isActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AlertDialog(
        title: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
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
                '${widget.folder.isEmpty ? 'My files' : widget.folder}',
                style: AppTextStyle.caption.copyWith(color: secondary),
              ),
              const SizedBox(height: AppDimens.space12),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                child: LinearProgressIndicator(value: progress, minHeight: 8),
              ),
              const SizedBox(height: AppDimens.space6),
              Text(
                '${Format.bytes(done)} of ${Format.bytes(total)}',
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
                    separatorBuilder: (_, __) => const SizedBox(height: AppDimens.space2),
                    itemBuilder: (_, index) => _buildRow(context, _items[index]),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (isActive)
            TextButton(onPressed: _cancel, child: const Text('Cancel'))
          else
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(failed > 0 ? 'Close' : 'Done'),
            ),
        ],
      ),
    );
  }

  Color successFor(Brightness b) => b == Brightness.dark ? AppColors.successDark : AppColors.successLight;

  Widget _buildRow(BuildContext context, TransferItem item) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final failed = item.status == 'queued' && item.error != null;
    final doneStatus = item.status == 'completed';
    final uploading = item.status == 'uploading';
    final frac = item.size == 0 ? 0.0 : (item.transferred / item.size).clamp(0.0, 1.0);

    final IconData icon;
    final Color color;
    final String label;
    if (doneStatus) {
      icon = Icons.check_circle_outline_rounded;
      color = successFor(brightness);
      label = 'Uploaded';
    } else if (failed) {
      icon = Icons.error_outline_rounded;
      color = brightness == Brightness.dark ? AppColors.errorDark : AppColors.errorLight;
      label = item.error ?? 'Failed';
    } else if (uploading) {
      icon = Icons.cloud_upload_outlined;
      color = AppColors.accentFor(brightness);
      label = '${Format.bytes(item.transferred)} / ${Format.bytes(item.size)}';
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
                          ? (brightness == Brightness.dark ? AppColors.errorDark : AppColors.errorLight)
                          : secondaryFor(brightness),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (failed)
            IconButton(
              tooltip: 'Retry',
              onPressed: () => _retry(item),
              icon: const Icon(Icons.refresh_rounded, size: AppDimens.iconSmall),
              color: brightness == Brightness.dark ? AppColors.errorDark : AppColors.errorLight,
            ),
        ],
      ),
    );
  }

  Color secondaryFor(Brightness b) => AppColors.textSecondaryFor(b);
}