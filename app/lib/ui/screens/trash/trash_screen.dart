import 'package:flutter/material.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/nexa_components.dart';

class TrashScreen extends StatefulWidget {
  final Api api;
  const TrashScreen({super.key, required this.api});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Map<String, dynamic>> _items = [];
  final Set<String> _selectedIds = <String>{};
  bool _loading = true;
  bool _emptying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.trash();
      if (!mounted) return;
      setState(() {
        _items = items;
        final ids = items.map((item) => item['id']?.toString() ?? '').toSet();
        _selectedIds.removeWhere((id) => !ids.contains(id));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // A failed load must never render as "Trash is empty".
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'Trash could not be loaded. Check your connection.';
        _loading = false;
      });
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_items.isNotEmpty && _selectedIds.length == _items.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_items.map((item) => item['id'].toString()));
      }
    });
  }

  void _toggleItem(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  Future<void> _restore(String id) async {
    try {
      await widget.api.restoreTrash(id);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((item) => item['id']?.toString() == id);
        _selectedIds.remove(id);
      });
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
          title: const Text('Delete forever?'),
          content: const Text(
            'This cannot be undone. The file will be permanently removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              child: const Text('Delete forever'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    try {
      await widget.api.permanentlyDeleteTrash(id);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((item) => item['id']?.toString() == id);
        _selectedIds.remove(id);
      });
      _toast('Permanently deleted');
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _deleteMany({required bool all}) async {
    final targets = all
        ? List<Map<String, dynamic>>.of(_items)
        : _items
            .where((item) => _selectedIds.contains(item['id']?.toString()))
            .toList(growable: false);
    if (targets.isEmpty || _emptying) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
          title: Text(all ? 'Empty Trash?' : 'Delete selected items?'),
          content: Text(
            'Permanently delete ${targets.length} '
            '${targets.length == 1 ? 'item' : 'items'}? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              child: Text(all ? 'Empty trash' : 'Delete selected'),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;

    setState(() => _emptying = true);
    final failedIds = <String>{};
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (next >= targets.length) return;
        final item = targets[next++];
        final id = item['id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          await widget.api.permanentlyDeleteTrash(id);
        } catch (_) {
          failedIds.add(id);
        }
      }
    }

    final workers = targets.length < 4 ? targets.length : 4;
    await Future.wait(List<Future<void>>.generate(workers, (_) => worker()));
    if (!mounted) return;

    final deleted = targets.length - failedIds.length;
    setState(() {
      _items.removeWhere(
        (item) => !failedIds.contains(item['id']?.toString()),
      );
      _selectedIds
        ..clear()
        ..addAll(failedIds);
      _emptying = false;
    });
    _toast(
      failedIds.isEmpty
          ? 'Trash emptied'
          : '$deleted deleted · ${failedIds.length} could not be deleted',
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: const StadiumBorder(),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomClearance = MediaQuery.paddingOf(context).bottom;
    final allSelected =
        _items.isNotEmpty && _selectedIds.length == _items.length;
    final deleteAll = _selectedIds.isEmpty || allSelected;

    return NexaPage(
      title: 'Trash',
      bottomSafeArea: false,
      subtitle: 'Deleted items are kept for 30 days',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_loading && _error == null && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppDimens.space12),
              child: NexaSurface(
                level: NexaSurfaceLevel.grouped,
                radius: AppDimens.radiusCard,
                padding: const EdgeInsets.all(AppDimens.space16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_items.length} ${_items.length == 1 ? 'item' : 'items'}',
                            style: AppTextStyle.titleMedium.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                          Text(
                            _selectedIds.isEmpty
                                ? 'Select items to restore or remove'
                                : '${_selectedIds.length} selected',
                            style: AppTextStyle.bodySmall.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _emptying ? null : _toggleSelectAll,
                      icon: Icon(
                        allSelected
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded,
                        size: AppDimens.iconSmall,
                      ),
                      label: Text(allSelected ? 'Clear' : 'Select'),
                    ),
                    const SizedBox(width: AppDimens.space4),
                    FilledButton(
                      onPressed:
                          _emptying ? null : () => _deleteMany(all: deleteAll),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                        shape: const StadiumBorder(),
                      ),
                      child: _emptying
                          ? SizedBox(
                              width: AppDimens.iconSmall,
                              height: AppDimens.iconSmall,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onError,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  deleteAll
                                      ? Icons.delete_sweep_outlined
                                      : Icons.delete_outline_rounded,
                                  size: AppDimens.iconSmall,
                                ),
                                const SizedBox(width: AppDimens.space8),
                                Text(deleteAll ? 'Empty' : 'Delete'),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: NexaStateSwitcher(
              stateKey: ValueKey(_bodyState),
              child: _loading
                  ? const NexaLoadingBlock()
                  : _error != null
                      ? NexaEmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Can’t load Trash',
                          hint: _error,
                          actionLabel: 'Retry',
                          onAction: load,
                        )
                      : _items.isEmpty
                          ? const NexaEmptyState(
                              icon: Icons.delete_outline_rounded,
                              title: 'Trash is empty',
                              hint:
                                  'Deleted files and folders will show up here.',
                            )
                          : RefreshIndicator(
                              onRefresh: load,
                              child: ListView(
                                padding: EdgeInsets.only(
                                  bottom: bottomClearance > AppDimens.space24
                                      ? bottomClearance
                                      : AppDimens.space24,
                                ),
                                children: [
                                  NexaGroupedList(
                                    header: 'Recently deleted',
                                    children: [
                                      for (final item in _items)
                                        _TrashRow(
                                          item: item,
                                          selected: _selectedIds.contains(
                                            item['id']?.toString() ?? '',
                                          ),
                                          onSelected: (value) => _toggleItem(
                                            item['id']?.toString() ?? '',
                                            value,
                                          ),
                                          onRestore: () => _restore(
                                            item['id']?.toString() ?? '',
                                          ),
                                          onDelete: () => _delete(
                                            item['id']?.toString() ?? '',
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
            ),
          ),
        ],
      ),
    );
  }

  String get _bodyState => _loading
      ? 'loading'
      : _error != null
          ? 'error'
          : _items.isEmpty
              ? 'empty'
              : 'content';
}

/// One trashed entry as a Material 3 tonal surface row.
class _TrashRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _TrashRow({
    required this.item,
    required this.selected,
    required this.onSelected,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isFolder = FileEntry.kindOf(item) == 'folder';
    final name = item['name']?.toString() ?? 'deleted item';
    final deletedAt = Format.relTime(
      DateTime.tryParse(item['deleted_at']?.toString() ?? ''),
    );

    return NexaGroupTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) => onSelected(value ?? false),
            semanticLabel: 'Select $name',
          ),
          const SizedBox(width: AppDimens.space4),
          SizedBox(
            width: AppDimens.iconTile,
            height: AppDimens.iconTile,
            child: Center(
              child: isFolder
                  ? const NexaFileGlyph.folder(size: 36)
                  : NexaFileGlyph(
                      name: name,
                      type: item['type']?.toString(),
                      size: 36,
                    ),
            ),
          ),
        ],
      ),
      title: item['name'] as String? ?? '',
      subtitle: 'Deleted $deletedAt',
      showChevron: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Restore',
            icon: Icon(Icons.restore_rounded, color: scheme.primary),
            onPressed: onRestore,
          ),
          IconButton(
            tooltip: 'Delete forever',
            icon: const Icon(Icons.delete_forever_outlined),
            color: scheme.error,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
