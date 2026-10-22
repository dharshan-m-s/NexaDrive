import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../services/upload_item.dart';
import '../../../services/upload_manager.dart';
import '../../widgets/nexa_components.dart';

/// Offline upload queue — every pending transfer, its progress, and retry.
class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  late final UploadManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = UploadManager.current;
    _manager.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    _manager.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle(UploadItem item) async {
    switch (item.state) {
      case UploadState.paused:
        await _manager.resume(item.id);
      case UploadState.failed:
      case UploadState.cancelled:
        await _manager.retry(item.id);
      case UploadState.completed:
        break;
      case UploadState.queued:
      case UploadState.uploading:
      case UploadState.retrying:
        await _manager.pause(item.id);
    }
    _refresh();
  }

  Future<void> _remove(UploadItem item) async {
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
    await _manager.remove(item.id);
    _refresh();
  }

  Future<void> _clearCompleted() async {
    await _manager.clearCompleted();
    _refresh();
  }

  Future<void> _retryAll() async {
    await _manager.retryFailed();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final items = _manager.items();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NexaPage(
          title: 'Transfers',
          subtitle: _summary(items),
          leading: const NexaBackButton(),
          headerAction: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (items
                  .any((UploadItem item) => item.state == UploadState.failed))
                IconButton(
                  tooltip: 'Retry failed',
                  onPressed: _retryAll,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              if (items.any(
                  (UploadItem item) => item.state == UploadState.completed))
                IconButton(
                  tooltip: 'Clear completed',
                  onPressed: _clearCompleted,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageMargin,
            0,
            AppDimens.pageMargin,
            AppDimens.space24,
          ),
          body: _body(items),
        ),
      ),
    );
  }

  /// One-line state of the queue, so the page says more than its title.
  String _summary(List<UploadItem> items) {
    if (items.isEmpty) return 'Queue is empty';
    final active = items
        .where((UploadItem item) =>
            item.state == UploadState.queued ||
            item.state == UploadState.uploading ||
            item.state == UploadState.retrying)
        .length;
    final failed = items
        .where((UploadItem item) => item.state == UploadState.failed)
        .length;
    if (active == 0 && failed == 0) return '${items.length} completed';
    final parts = <String>[];
    if (active > 0) parts.add('$active active');
    if (failed > 0) parts.add('$failed failed');
    return '${parts.join(' · ')} of ${items.length}';
  }

  /// The body, cross-faded between states so a resolved queue settles in.
  Widget _body(List<UploadItem> items) => NexaStateSwitcher(
        stateKey: ValueKey(_bodyState(items)),
        child: _buildBody(items),
      );

  String _bodyState(List<UploadItem> items) =>
      items.isEmpty ? 'empty' : 'content';

  Widget _buildBody(List<UploadItem> items) {
    if (items.isEmpty) {
      return const NexaEmptyState(
        icon: Icons.cloud_upload_outlined,
        title: 'No transfers',
        hint: 'Uploads you start while offline will be queued here.',
      );
    }
    final active = items
        .where((UploadItem item) =>
            item.state == UploadState.queued ||
            item.state == UploadState.uploading ||
            item.state == UploadState.retrying ||
            item.state == UploadState.paused)
        .toList();
    final completed = items
        .where((UploadItem item) => item.state == UploadState.completed)
        .toList();
    final failed = items
        .where((UploadItem item) =>
            item.state == UploadState.failed ||
            item.state == UploadState.cancelled)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space8,
        AppDimens.pageMargin,
        AppDimens.space24,
      ),
      children: [
        if (active.isNotEmpty)
          _Section(
              'Uploading',
              '${Format.bytes(active.fold<int>(0, (int s, UploadItem e) => s + e.transferred))} '
                  'of ${Format.bytes(active.fold<int>(0, (int s, UploadItem e) => s + e.size))}'),
        for (final item in active)
          _TransferRow(item: item, onToggle: _toggle, onRemove: _remove),
        if (failed.isNotEmpty) ...[
          const SizedBox(height: AppDimens.space16),
          _Section('Needs attention', '${failed.length} failed'),
          for (final item in failed)
            _TransferRow(item: item, onToggle: _toggle, onRemove: _remove),
        ],
        if (completed.isNotEmpty) ...[
          const SizedBox(height: AppDimens.space16),
          _Section('Completed', '${completed.length} done'),
          for (final item in completed)
            _TransferRow(item: item, onToggle: null, onRemove: _remove),
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
        AppDimens.space4,
        AppDimens.space12,
        AppDimens.space4,
        AppDimens.space8,
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
  final UploadItem item;
  final Future<void> Function(UploadItem)? onToggle;
  final Future<void> Function(UploadItem)? onRemove;

  const _TransferRow({required this.item, this.onToggle, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final state = item.state;
    final completed = state == UploadState.completed;
    final failed =
        state == UploadState.failed || state == UploadState.cancelled;
    final uploading =
        state == UploadState.uploading || state == UploadState.retrying;
    final paused = state == UploadState.paused;
    final frac = item.progress;

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
      statusColor = paused ? AppColors.textSecondaryFor(brightness) : accent;
      trailing = IconButton(
        tooltip: paused ? 'Resume' : 'Pause',
        icon: Icon(
          paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          color: statusColor,
        ),
        onPressed: onToggle == null ? null : () => onToggle!(item),
      );
    }

    return NexaSurface(
      level: NexaSurfaceLevel.surface,
      margin: const EdgeInsets.only(bottom: AppDimens.space8),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space16,
        AppDimens.space12,
        AppDimens.space8,
        AppDimens.space12,
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
                            : paused
                                ? Icons.pause_circle_outline_rounded
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
                  _label(state, item),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption.copyWith(
                    color: failed
                        ? statusColor
                        : AppColors.textSecondaryFor(brightness),
                  ),
                ),
                if (!completed && !failed) ...[
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

  static String _label(UploadState state, UploadItem item) {
    switch (state) {
      case UploadState.completed:
        return 'Uploaded';
      case UploadState.failed:
        return item.error ?? 'Failed';
      case UploadState.cancelled:
        return 'Cancelled';
      case UploadState.paused:
        return 'Paused · ${Format.bytes(item.transferred)} of ${Format.bytes(item.size)}';
      case UploadState.uploading:
        return '${Format.bytes(item.transferred)} / ${Format.bytes(item.size)}';
      case UploadState.retrying:
        return 'Retrying…';
      case UploadState.queued:
        return 'Waiting…';
    }
  }
}
