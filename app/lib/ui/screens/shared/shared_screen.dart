import 'package:flutter/material.dart';

import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../services/api.dart';
import '../../widgets/nexa_components.dart';
import 'shared_browse_screen.dart';

enum _SharedPageAction { refresh, toggleSort }

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
  bool _descending = false;
  String? _error;
  String? _openingShareId;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.shared(),
        widget.api.shares(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _shared = results[0];
        _shares = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = 'Check your server connection and try again.';
      });
    }
  }

  String _displayName(Map<String, dynamic> share) {
    final path = share['path']?.toString() ?? '';
    final name = path.split('/').last;
    return name.isEmpty ? 'Shared item' : name;
  }

  Future<void> _openShare(Map<String, dynamic> share) async {
    final id = share['id']?.toString() ?? '';
    if (id.isEmpty || _openingShareId == id) return;
    setState(() => _openingShareId = id);
    try {
      final items = await widget.api.sharedItems(id, '');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SharedBrowseScreen(
            api: widget.api,
            shareId: id,
            path: '',
            initialItems: items,
            title: _displayName(share),
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showMessage(e.toString());
    } finally {
      if (mounted && _openingShareId == id) {
        setState(() => _openingShareId = null);
      }
    }
  }

  Future<void> _deleteShare(Map<String, dynamic> share) async {
    final id = share['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.link_off_rounded, color: scheme.error),
          title: const Text('Stop sharing?'),
          content: Text(
            'This revokes the recipient’s access to “${_displayName(share)}”. '
            'The file or folder itself will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    try {
      await widget.api.deleteShare(id);
      if (mounted) await load();
    } catch (e) {
      if (mounted) _showMessage(e.toString());
    }
  }

  Future<void> _leaveShare(Map<String, dynamic> share) async {
    final id = share['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.link_off_rounded, color: scheme.error),
          title: const Text('Remove from Shared with me?'),
          content: Text(
            'You will lose access to “${_displayName(share)}”. '
            'The owner’s original file will not be changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove access'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    try {
      await widget.api.leaveShare(id);
      if (mounted) await load();
    } catch (e) {
      if (mounted) _showMessage(e.toString());
    }
  }

  void _showMessage(String message) {
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

  String _shareSubtitle(Map<String, dynamic> item) {
    if (!_mine) {
      final owner =
          (item['owner'] ?? item['owner_username'])?.toString().trim() ?? '';
      final permission =
          item['permission']?.toString() == 'write' ? 'Can edit' : 'Can view';
      final sender = owner.isEmpty ? 'Shared with you' : 'Shared by $owner';
      return '$sender · $permission';
    }

    final recipient = item['recipient']?.toString().trim() ?? '';
    final permission = item['permission'] == 'write' ? 'Can edit' : 'Can view';
    final target = item['is_link'] == true
        ? 'Public link'
        : recipient.isEmpty
            ? 'Shared by you'
            : 'Shared with $recipient';
    final expiresAt = DateTime.tryParse(item['expires_at']?.toString() ?? '');
    final expiry = expiresAt == null
        ? ''
        : ' · Expires ${expiresAt.toLocal().day.toString().padLeft(2, '0')}/'
            '${expiresAt.toLocal().month.toString().padLeft(2, '0')}/'
            '${expiresAt.toLocal().year}';
    return '$target · $permission$expiry';
  }

  List<Map<String, dynamic>> get _visibleItems {
    final items = List<Map<String, dynamic>>.from(_mine ? _shares : _shared);
    items.sort(
      (a, b) => _displayName(a).toLowerCase().compareTo(
            _displayName(b).toLowerCase(),
          ),
    );
    return _descending ? items.reversed.toList(growable: false) : items;
  }

  @override
  Widget build(BuildContext context) {
    final count = _visibleItems.length;
    return NexaPage(
      title: 'Shared',
      subtitle: '$count ${_mine ? 'active shares' : 'shared items'}',
      bottomSafeArea: false,
      headerAction: PopupMenuButton<_SharedPageAction>(
        tooltip: 'Shared page actions',
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (action) {
          switch (action) {
            case _SharedPageAction.refresh:
              load();
              break;
            case _SharedPageAction.toggleSort:
              setState(() => _descending = !_descending);
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: _SharedPageAction.refresh,
            child: Row(
              children: [
                Icon(Icons.refresh_rounded, size: AppDimens.iconSmall),
                SizedBox(width: AppDimens.space12),
                Text('Refresh shares'),
              ],
            ),
          ),
          PopupMenuItem(
            value: _SharedPageAction.toggleSort,
            child: Row(
              children: [
                const Icon(Icons.sort_by_alpha_rounded,
                    size: AppDimens.iconSmall),
                const SizedBox(width: AppDimens.space12),
                Text(_descending ? 'Sort A–Z' : 'Sort Z–A'),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShareScopeSwitch(
            mine: _mine,
            receivedCount: _shared.length,
            sentCount: _shares.length,
            onChanged: (value) => setState(() => _mine = value),
          ),
          const SizedBox(height: AppDimens.space12),
          Expanded(child: _body()),
        ],
      ),
      scrollable: false,
    );
  }

  Widget _body() => NexaStateSwitcher(
        stateKey: ValueKey(_bodyState),
        child: _buildBody(),
      );

  String get _bodyState {
    final scope = _mine ? 'mine' : 'received';
    if (_loading) return '$scope:loading';
    if (_error != null) return '$scope:error';
    return _visibleItems.isEmpty ? '$scope:empty' : '$scope:content';
  }

  Widget _buildBody() {
    final scheme = Theme.of(context).colorScheme;
    final items = _visibleItems;
    final bottomClearance = MediaQuery.paddingOf(context).bottom;

    if (_loading) return const NexaLoadingBlock();

    if (_error != null) {
      return _SharedConnectionNotice(onRetry: load);
    }

    if (items.isEmpty) {
      return NexaEmptyState(
        icon: _mine ? Icons.link_rounded : Icons.inbox_outlined,
        title: _mine ? 'No active shares' : 'Nothing shared with you',
        hint: _mine
            ? 'Share a file from My files to create a link.'
            : 'New shares will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: bottomClearance > AppDimens.space24
              ? bottomClearance
              : AppDimens.space24,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.rowInset,
              AppDimens.space8,
              AppDimens.rowInset,
              AppDimens.space12,
            ),
            child: Text(
              (_mine ? 'Shared by you' : 'Shared with you').toUpperCase(),
              style: AppTextStyle.sectionHeader.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (var i = 0; i < items.length; i++) ...[
            NexaSharedTile(
              name: _displayName(items[i]),
              path: items[i]['path']?.toString() ?? '',
              isFolder: FileEntry.kindOf(items[i]) == 'folder',
              person: _mine
                  ? items[i]['recipient']?.toString()
                  : (items[i]['owner'] ?? items[i]['owner_username'])
                      ?.toString(),
              subtitle: _shareSubtitle(items[i]),
              loading: _openingShareId == items[i]['id']?.toString() && !_mine,
              trailing: IconButton(
                tooltip: _mine ? 'Stop sharing' : 'Remove from Shared with me',
                onPressed: _mine
                    ? () => _deleteShare(items[i])
                    : () => _leaveShare(items[i]),
                icon: Icon(Icons.link_off_rounded, color: scheme.error),
              ),
              onTap: _mine ? null : () => _openShare(items[i]),
            ),
            if (i < items.length - 1)
              Divider(
                height: 1,
                indent: AppDimens.rowInset +
                    AppDimens.iconTileLarge +
                    AppDimens.space16,
                endIndent: AppDimens.rowInset,
                color: scheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _SharedConnectionNotice extends StatelessWidget {
  final VoidCallback onRetry;
  const _SharedConnectionNotice({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.space16),
      child: NexaSurface(
        level: NexaSurfaceLevel.grouped,
        radius: AppDimens.radiusCard,
        padding: const EdgeInsets.all(AppDimens.space16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off_rounded,
                    color: scheme.error, size: AppDimens.iconMedium),
                const SizedBox(width: AppDimens.space12),
                Text(
                  'Connection problem',
                  style: AppTextStyle.titleMedium.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space8),
            Text(
              'NexaDrive could not contact your server. Check that the server '
              'is online and your device is connected.',
              style: AppTextStyle.bodyMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppDimens.space12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded,
                    size: AppDimens.iconSmall),
                label: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareScopeSwitch extends StatelessWidget {
  final bool mine;
  final int receivedCount;
  final int sentCount;
  final ValueChanged<bool> onChanged;

  const _ShareScopeSwitch({
    required this.mine,
    required this.receivedCount,
    required this.sentCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment<bool>(
          value: false,
          label: Text('With me ($receivedCount)'),
        ),
        ButtonSegment<bool>(
          value: true,
          label: Text('Shared by me ($sentCount)'),
        ),
      ],
      selected: <bool>{mine},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
    );
  }
}
