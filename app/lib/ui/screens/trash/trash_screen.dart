import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_page.dart';
import '../../widgets/one_ui_surface.dart';

class TrashScreen extends StatefulWidget {
  final Api api;
  const TrashScreen({super.key, required this.api});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.api.trash();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _restore(String id) async {
    try {
      await widget.api.restoreTrash(id);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete forever?'),
        content: const Text('This cannot be undone. The file will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.api.permanentlyDeleteTrash(id);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return OneUiPage(
      title: 'Trash',
      subtitle: 'Deleted items are kept for 30 days',
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _items.isEmpty
              ? const OneUiEmptyState(
                  icon: Icons.delete_outline_rounded,
                  title: 'Trash is empty',
                  hint: 'Deleted files and folders will show up here.',
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: AppDimens.space24),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppDimens.space2),
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      final isFolder = (item['type'] as String? ?? 'file') == 'folder';
                      final deletedAt =
                          Format.relTime(DateTime.tryParse(item['deleted_at']?.toString() ?? ''));
                      return OneUiSurface(
                        level: OneUiSurfaceLevel.surface,
                        radius: AppDimens.radiusTile,
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppDimens.radiusTile),
                          ),
                          leading: Icon(
                            isFolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                            size: AppDimens.iconMedium,
                            color: isFolder
                                ? AppColors.accentFor(brightness)
                                : null,
                          ),
                          title: Text(
                            item['name'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text('Deleted $deletedAt'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Restore',
                                icon: Icon(
                                  Icons.restore_rounded,
                                  color: AppColors.accentFor(brightness),
                                ),
                                onPressed: () => _restore(item['id'] as String),
                              ),
                              IconButton(
                                tooltip: 'Delete forever',
                                icon: const Icon(Icons.delete_forever_outlined),
                                color: AppColors.errorFor(brightness),
                                onPressed: () => _delete(item['id'] as String),
                              ),
                            ],
                          ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}