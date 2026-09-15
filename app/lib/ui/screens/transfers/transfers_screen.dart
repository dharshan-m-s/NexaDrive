import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/transfer_queue.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_surface.dart';

/// Offline upload queue — every pending transfer, its progress, and retry.
class TransfersScreen extends StatefulWidget {
  final Api api;
  const TransfersScreen({super.key, required this.api});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  List<TransferItem> _items = [];
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final queue = TransferQueue(widget.api);
    final items = await queue.items();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _process() async {
    setState(() => _processing = true);
    await TransferQueue(widget.api).process(onChanged: (_) => _refresh());
    await _refresh();
    if (mounted) setState(() => _processing = false);
  }

  Future<void> _resumeOrPause(TransferItem item) async {
    final queue = TransferQueue(widget.api);
    if (item.status == 'queued' && item.error != null) {
      await queue.reset(item.id);
    } else {
      await queue.pause(item.id);
    }
    await _refresh();
    if (item.status != 'completed') await _process();
  }

  Future<void> _remove(TransferItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove upload'),
        content: Text('Remove "${item.name}" from the queue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await TransferQueue(widget.api).remove(item.id);
    await _refresh();
  }

  Future<void> _clearCompleted() async {
    await TransferQueue(widget.api).clearCompleted();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
        actions: [
          IconButton(
            tooltip: 'Process queue',
            onPressed: _processing
                ? null
                : () {
                    _process();
                  },
            icon: Icon(
              _processing
                  ? Icons.hourglass_top_rounded
                  : Icons.play_arrow_rounded,
            ),
          ),
          if (_items.any((e) => e.status == 'completed'))
            IconButton(
              tooltip: 'Clear completed',
              onPressed: _clearCompleted,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_items.isEmpty) {
      return const OneUiEmptyState(
        icon: Icons.cloud_upload_outlined,
        title: 'No transfers',
        hint: 'Uploads you start while offline will be queued here.',
      );
    }
    final active = _items
        .where((e) => e.status != 'completed' && !(e.status == 'queued' && e.error != null))
        .toList();
    final completed = _items.where((e) => e.status == 'completed').toList();
    final failed = _items
        .where((e) => e.status == 'queued' && e.error != null)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin, AppDimens.space8, AppDimens.pageMargin, AppDimens.space24,
      ),
      children: [
        if (active.isNotEmpty)
          _Section('Uploading',
              '${Format.bytes(active.fold<int>(0, (s, e) => s + e.transferred))} '
              'of ${Format.bytes(active.fold<int>(0, (s, e) => s + e.size))}'),
        for (final item in active) _TransferRow(item: item, onToggle: _resumeOrPause, onRemove: _remove),
        if (failed.isNotEmpty) ...[
          const SizedBox(height: AppDimens.space16),
          _Section('Needs attention', '${failed.length} failed'),
          for (final item in failed) _TransferRow(item: item, onToggle: _resumeOrPause, onRemove: _remove),
        ],
        if (completed.isNotEmpty) ...[
          const SizedBox(height: AppDimens.space16),
          _Section('Completed', '${completed.length} done'),
          for (final item in completed) _TransferRow(item: item, onToggle: null, onRemove: null),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String detail;
  const _Section(this.title, this.detail);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space4, AppDimens.space12, AppDimens.space4, AppDimens.space8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: AppTextStyle.listHeader.copyWith(
              color: AppColors.textTertiaryFor(brightness),
              letterSpacing: 0.6,
            ),
          ),
          Text(
            detail,
            style: AppTextStyle.micro.copyWith(
              color: AppColors.textTertiaryFor(brightness),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  final TransferItem item;
  final Future<void> Function(TransferItem)? onToggle;
  final Future<void> Function(TransferItem)? onRemove;

  const _TransferRow({required this.item, this.onToggle, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final completed = item.status == 'completed';
    final failed = item.status == 'queued' && item.error != null;
    final uploading = item.status == 'uploading';
    final frac = item.size == 0 ? 0.0 : (item.transferred / item.size).clamp(0.0, 1.0);

    final accent = AppColors.accentFor(brightness);
    final Color statusColor;
    final Widget? trailing;
    if (failed) {
      statusColor = AppColors.errorFor(brightness);
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Retry',
            icon: Icon(Icons.refresh_rounded, color: statusColor),
            onPressed: onToggle == null ? null : () => onToggle!(item),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close_rounded),
            onPressed: onRemove == null ? null : () => onRemove!(item),
          ),
        ],
      );
    } else if (completed) {
      statusColor = AppColors.successFor(brightness);
      trailing = IconButton(
        tooltip: 'Remove',
        icon: const Icon(Icons.close_rounded),
        onPressed: onRemove == null ? null : () => onRemove!(item),
      );
    } else {
      statusColor = accent;
      trailing = IconButton(
        tooltip: 'Pause',
        icon: Icon(Icons.pause_rounded, color: accent),
        onPressed: onToggle == null ? null : () => onToggle!(item),
      );
    }

    return OneUiSurface(
      level: OneUiSurfaceLevel.surface,
      margin: const EdgeInsets.only(bottom: AppDimens.space8),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space16, AppDimens.space12, AppDimens.space8, AppDimens.space12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    completed
                        ? Icons.check_circle_outline_rounded
                        : failed
                            ? Icons.error_outline_rounded
                            : Icons.schedule_rounded,
                    size: 20,
                    color: statusColor,
                  ),
          ),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.rowTitle.copyWith(
                    color: AppColors.textPrimaryFor(brightness),
                  ),
                ),
                const SizedBox(height: AppDimens.space2),
                Text(
                  failed
                      ? (item.error ?? 'Failed')
                      : uploading
                          ? '${Format.bytes(item.transferred)} / ${Format.bytes(item.size)}'
                          : completed
                              ? 'Uploaded'
                              : 'Waiting…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption.copyWith(
                    color: failed ? statusColor : AppColors.textSecondaryFor(brightness),
                  ),
                ),
                if (uploading) ...[
                  const SizedBox(height: AppDimens.space6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 4,
                      backgroundColor: accent.withValues(alpha: 0.18),
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                ],
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}