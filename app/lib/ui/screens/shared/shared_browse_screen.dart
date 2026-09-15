import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/one_ui_empty_state.dart';

/// Browse the contents of a folder shared with this user.
class SharedBrowseScreen extends StatefulWidget {
  final Api api;
  final String shareId;
  final String path;
  final List<Map<String, dynamic>> initialItems;
  final String title;

  const SharedBrowseScreen({
    super.key,
    required this.api,
    required this.shareId,
    required this.path,
    required this.initialItems,
    required this.title,
  });

  @override
  State<SharedBrowseScreen> createState() => _SharedBrowseScreenState();
}

class _SharedBrowseScreenState extends State<SharedBrowseScreen> {
  late String path;
  late List<Map<String, dynamic>> items;
  String? _error;

  @override
  void initState() {
    super.initState();
    path = widget.path;
    items = widget.initialItems;
  }

  Future<void> load(String p) async {
    try {
      final result = await widget.api.sharedItems(widget.shareId, p);
      if (mounted) {
        setState(() {
          items = result;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _download(Map<String, dynamic> item) async {
    try {
      final fullPath = item['path'] as String;
      final name = item['name'] as String? ?? fullPath.split('/').last;
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save $name',
        fileName: name,
        bytes: Uint8List(0),
      );
      final outPath = uri?.toFilePath();
      if (outPath == null) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download started…')),
      );
      await widget.api.downloadToFile(fullPath, outPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Downloaded')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _open(Map<String, dynamic> item) {
    final type = item['type'] as String? ?? 'file';
    final name = item['name'] as String? ?? '';
    if (type != 'folder') {
      _download(item);
      return;
    }
    final newPath = (path.isEmpty ? '' : '$path/') + name;
    setState(() => path = newPath);
    load(newPath);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final secondary = AppColors.textSecondaryFor(brightness);

    return Scaffold(
      appBar: AppBar(
        title: Text(path.isEmpty ? widget.title : path.split('/').last),
        actions: [
          IconButton(
            tooltip: 'Up one level',
            onPressed: path.isEmpty
                ? null
                : () {
                    final idx = path.lastIndexOf('/');
                    final parent = idx < 0 ? '' : path.substring(0, idx);
                    setState(() => path = parent);
                    load(parent);
                  },
            icon: Icon(Icons.arrow_upward_rounded, color: accent),
          ),
        ],
      ),
      body: _error != null
          ? OneUiEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Can\'t load this folder',
              hint: _error,
              actionLabel: 'Retry',
              onAction: () => load(path),
            )
          : items.isEmpty
              ? const OneUiEmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'This folder is empty',
                  hint: 'There\'s nothing here to download.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.pageMargin,
                    AppDimens.space8,
                    AppDimens.pageMargin,
                    AppDimens.space24,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppDimens.space2),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final type = item['type'] as String? ?? 'file';
                    final isFolder = type == 'folder';
                    final name = item['name'] as String? ?? '';
                    final size = (item['size'] as num?)?.toInt();
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimens.radiusTile),
                      ),
                      leading: Container(
                        width: AppDimens.iconTileLarge,
                        height: AppDimens.iconTileLarge,
                        decoration: BoxDecoration(
                          color: brightness == Brightness.dark
                              ? accent.withValues(alpha: 0.18)
                              : accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppDimens.radiusInner),
                        ),
                        child: Icon(
                          isFolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                          color: isFolder ? accent : null,
                          size: AppDimens.iconMedium,
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: isFolder
                          ? null
                          : Text(
                              Format.bytes(size),
                              style: TextStyle(
                                fontSize: 12,
                                color: secondary,
                              ),
                            ),
                      trailing: isFolder
                          ? Icon(Icons.chevron_right_rounded, color: secondary)
                          : IconButton(
                              tooltip: 'Download',
                              icon: const Icon(Icons.download_outlined),
                              onPressed: () => _download(item),
                            ),
                      onTap: () => _open(item),
                    );
                  },
                ),
    );
  }
}