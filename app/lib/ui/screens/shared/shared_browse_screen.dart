import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/utils/format.dart';
import '../../../core/models/file_entry.dart';
import '../../../services/api.dart';
import '../../widgets/nexa_components.dart';

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
  final Set<String> _downloading = <String>{};
  String? _error;
  bool _loading = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    path = widget.path;
    items = widget.initialItems;
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  Future<void> load(String target) async {
    final generation = ++_loadGeneration;
    setState(() {
      if (target != path) items = const [];
      path = target;
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.sharedItems(widget.shareId, target);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        items = result;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _download(Map<String, dynamic> item) async {
    final fullPath = item['path']?.toString() ?? '';
    if (fullPath.isEmpty || _downloading.contains(fullPath)) return;
    final name = item['name']?.toString() ?? fullPath.split('/').last;
    setState(() => _downloading.add(fullPath));
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save $name',
        fileName: name,
        bytes: Uint8List(0),
      );
      final outPath = uri?.toFilePath();
      if (outPath == null) return;
      if (!mounted) return;
      await widget.api.downloadToFile(fullPath, outPath);
      if (mounted) _showMessage('Saved $name');
    } catch (e) {
      if (mounted) _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _downloading.remove(fullPath));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _open(Map<String, dynamic> item) {
    if (FileEntry.kindOf(item) != 'folder') {
      _download(item);
      return;
    }
    final name = item['name']?.toString() ?? '';
    if (name.isEmpty) return;
    final nextPath = path.isEmpty ? name : '$path/$name';
    load(nextPath);
  }

  String get _title => path.isEmpty ? widget.title : path.split('/').last;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NexaPage(
          title: _title,
          subtitle: path.isEmpty ? null : path,
          leading: NexaLiquidGlass(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            padding: EdgeInsets.zero,
            blurSigma: 10,
            showShadow: false,
            child: const NexaBackButton(),
          ),
          headerAction: path.isEmpty
              ? null
              : NexaLiquidGlass(
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  padding: EdgeInsets.zero,
                  blurSigma: 10,
                  showShadow: false,
                  child: IconButton(
                    tooltip: 'Up one level',
                    onPressed: () {
                      final index = path.lastIndexOf('/');
                      final parent = index < 0 ? '' : path.substring(0, index);
                      load(parent);
                    },
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ),
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageMargin,
            AppDimens.space8,
            AppDimens.pageMargin,
            AppDimens.space24,
          ),
          body: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final bottomClearance = MediaQuery.paddingOf(context).bottom;
    if (_loading && items.isEmpty) return const NexaLoadingBlock();
    if (_error != null && items.isEmpty) {
      return NexaEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Folder unavailable',
        hint: _error,
        actionLabel: 'Retry',
        onAction: () => load(path),
      );
    }
    if (items.isEmpty) {
      return const NexaEmptyState(
        icon: Icons.folder_open_rounded,
        title: 'This folder is empty',
        hint: 'No items to display.',
      );
    }

    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: bottomClearance > AppDimens.space24
            ? bottomClearance
            : AppDimens.space24,
      ),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(bottom: AppDimens.space8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        NexaGroupedList(
          header: '${items.length} ${items.length == 1 ? 'ITEM' : 'ITEMS'}',
          children: [
            for (final item in items) _sharedItemRow(item),
          ],
        ),
      ],
    );

    return RefreshIndicator(
      onRefresh: () => load(path),
      child: content,
    );
  }

  Widget _sharedItemRow(Map<String, dynamic> item) {
    final brightness = Theme.of(context).brightness;
    final isFolder = FileEntry.kindOf(item) == 'folder';
    final fullPath = item['path']?.toString() ?? '';
    final name = item['name']?.toString() ??
        (fullPath.isEmpty ? 'Shared item' : fullPath.split('/').last);
    final size = (item['size'] as num?)?.toInt();
    final isDownloading = _downloading.contains(fullPath);

    return NexaGroupTile(
      leadingIcon:
          isFolder ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
      leadingIconColor: AppColors.accentTextFor(brightness),
      leadingBackgroundColor: AppColors.accentContainerFor(brightness),
      title: name,
      subtitle: isFolder ? 'Folder' : Format.bytes(size),
      showChevron: isFolder,
      trailing: isFolder
          ? null
          : NexaLiquidGlass(
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
              padding: EdgeInsets.zero,
              blurSigma: 9,
              showShadow: false,
              child: IconButton(
                tooltip: 'Download',
                onPressed: isDownloading ? null : () => _download(item),
                icon: isDownloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
              ),
            ),
      onTap: () => _open(item),
    );
  }
}
