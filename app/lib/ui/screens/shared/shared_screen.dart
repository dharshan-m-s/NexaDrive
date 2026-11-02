import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
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
      builder: (dialogContext) => AlertDialog(
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
      ),
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
      builder: (dialogContext) => AlertDialog(
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
      ),
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
      ..showSnackBar(SnackBar(content: Text(message)));
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
                Icon(Icons.refresh_rounded, size: 18),
                SizedBox(width: AppDimens.space10),
                Text('Refresh shares'),
              ],
            ),
          ),
          PopupMenuItem(
            value: _SharedPageAction.toggleSort,
            child: Row(
              children: [
                const Icon(Icons.sort_by_alpha_rounded, size: 18),
                const SizedBox(width: AppDimens.space10),
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
    final brightness = Theme.of(context).brightness;
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
          NexaGroupedList(
            header: _mine ? 'SHARED BY YOU' : 'SHARED WITH YOU',
            children: [
              for (final item in items)
                NexaGroupTile(
                  leadingIcon: _mine
                      ? Icons.link_rounded
                      : FileEntry.kindOf(item) == 'folder'
                          ? Icons.folder_shared_rounded
                          : Icons.insert_drive_file_outlined,
                  leadingIconColor: AppColors.accentTextFor(brightness),
                  leadingBackgroundColor:
                      AppColors.accentContainerFor(brightness),
                  title: _displayName(item),
                  subtitle: _shareSubtitle(item),
                  showChevron: !_mine,
                  trailing: _openingShareId == item['id']?.toString() && !_mine
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : IconButton(
                          tooltip: _mine
                              ? 'Stop sharing'
                              : 'Remove from Shared with me',
                          onPressed: _mine
                              ? () => _deleteShare(item)
                              : () => _leaveShare(item),
                          icon: Icon(
                            Icons.link_off_rounded,
                            color: AppColors.errorFor(brightness),
                            size: 20,
                          ),
                        ),
                  onTap: _mine ? null : () => _openShare(item),
                ),
            ],
          ),
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
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.space16),
      child: Container(
        padding: const EdgeInsets.all(AppDimens.space16),
        decoration: BoxDecoration(
          color: AppColors.surfaceFor(brightness),
          borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
          border: Border.all(color: AppColors.dividerFor(brightness)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off_rounded,
                    color: AppColors.errorFor(brightness), size: 20),
                const SizedBox(width: AppDimens.space8),
                Text('Connection problem',
                    style: TextStyle(
                      color: AppColors.labelPrimaryFor(brightness),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            const SizedBox(height: AppDimens.space8),
            Text(
              'NexaDrive could not contact your server. Check that the server is online and your device is connected.',
              style: TextStyle(
                color: AppColors.labelSecondaryFor(brightness),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppDimens.space12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
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
    final brightness = Theme.of(context).brightness;
    return Column(
      children: [
        Row(
          children: [
            _ShareScopeOption(
              label: 'With me',
              count: receivedCount,
              selected: !mine,
              onTap: () => onChanged(false),
            ),
            const SizedBox(width: AppDimens.space24),
            _ShareScopeOption(
              label: 'Shared by me',
              count: sentCount,
              selected: mine,
              onTap: () => onChanged(true),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space8),
        Stack(
          children: [
            Container(height: 1, color: AppColors.dividerFor(brightness)),
            AnimatedAlign(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              duration: AppMotion.resolve(context, AppMotion.normal),
              curve: AppMotion.standardCurve,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: AppColors.accentFor(brightness),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShareScopeOption extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _ShareScopeOption({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label, $count',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.space10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: AppTextStyle.subheadline.copyWith(
                    color: selected
                        ? AppColors.labelPrimaryFor(brightness)
                        : AppColors.labelSecondaryFor(brightness),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AppDimens.space8),
                AnimatedContainer(
                  duration: AppMotion.resolve(context, AppMotion.fast),
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space6,
                    vertical: AppDimens.space2,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accentContainerFor(brightness)
                        : AppColors.fillFor(brightness),
                    borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: AppTextStyle.caption2.copyWith(
                      color: selected
                          ? AppColors.accentTextFor(brightness)
                          : AppColors.labelSecondaryFor(brightness),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
