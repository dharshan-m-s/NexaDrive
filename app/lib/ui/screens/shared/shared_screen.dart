import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../services/api.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_grouped_list.dart';
import '../../widgets/one_ui_page.dart';
import 'shared_browse_screen.dart';

class SharedScreen extends StatefulWidget {
  final Api api;
  const SharedScreen({super.key, required this.api});

  @override
  State<SharedScreen> createState() => _SharedScreenState();
}

class _SharedScreenState extends State<SharedScreen> {
  List<Map<String, dynamic>> _shared = [];
  List<Map<String, dynamic>> _shares = [];
  bool _loading = true;
  bool _mine = false;
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
      final results = await Future.wait([
        widget.api.shared(),
        widget.api.shares(),
      ]);
      if (!mounted) return;
      setState(() {
        _shared = results[0];
        _shares = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _displayName(Map<String, dynamic> share) =>
      (share['path'] as String? ?? '').split('/').last;

  Future<void> _openShare(Map<String, dynamic> share) async {
    try {
      final items = await widget.api.sharedItems(share['id'] as String, '');
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SharedBrowseScreen(
            api: widget.api,
            shareId: share['id'] as String,
            path: '',
            initialItems: items,
            title: _displayName(share),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteShare(Map<String, dynamic> share) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove share'),
        content: Text('Remove access to "${_displayName(share)}"?'),
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
    if (confirm != true) return;
    try {
      await widget.api.deleteShare(share['id'] as String);
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
    return OneUiPage(
      title: _mine ? 'My shares' : 'Shared with me',
      subtitle: _mine
          ? 'Links and access you have granted'
          : 'Files and folders shared with you',
      headerAction: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('With me')),
          ButtonSegment(value: true, label: Text('Mine')),
        ],
        selected: {_mine},
        onSelectionChanged: (v) => setState(() => _mine = v.first),
        showSelectedIcon: false,
      ),
      body: _buildBody(),
      scrollable: false,
    );
  }

  Widget _buildBody() {
    final brightness = Theme.of(context).brightness;
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return OneUiEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Can\'t load shares',
        hint: _error,
        actionLabel: 'Retry',
        onAction: load,
      );
    }
    final items = _mine ? _shares : _shared;
    if (items.isEmpty) {
      return OneUiEmptyState(
        icon: _mine ? Icons.link_rounded : Icons.inbox_rounded,
        title: _mine ? 'No shares yet' : 'Nothing shared with you',
        hint: _mine
            ? 'Share a file or folder and it will show up here.'
            : 'Files shared with you will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: AppDimens.space24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppDimens.space2),
        itemBuilder: (context, i) {
          final item = items[i];
          final name = item['path']?.toString().split('/').last ?? '';
          final subtitle = _mine
              ? (item['permission'] == 'write' ? 'Read & write' : 'Read only')
              : 'Shared by ${item['owner_username'] ?? 'someone'}';
          return OneUiGroupTile(
            icon: _mine ? Icons.link_rounded : Icons.inbox_rounded,
            title: name,
            subtitle: subtitle,
            showChevron: !_mine,
            trailing: _mine
                ? IconButton(
                    tooltip: 'Remove share',
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.errorFor(brightness),
                    ),
                    onPressed: () => _deleteShare(item),
                  )
                : null,
            onTap: _mine ? null : () => _openShare(item),
          );
        },
      ),
    );
  }
}