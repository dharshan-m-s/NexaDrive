import 'package:flutter/material.dart';

import '../../../core/design/app_dimensions.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/nexa_components.dart';

class NotificationsScreen extends StatefulWidget {
  final Api api;
  const NotificationsScreen({super.key, required this.api});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _unreadOnly = false;
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _requestGeneration++;
    super.dispose();
  }

  Future<void> load() async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.notifications(unreadOnly: _unreadOnly);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loading = false;
        _error = e is ApiException
            ? e.message
            : 'Notifications could not be loaded. Check your connection.';
      });
    }
  }

  Future<void> _markRead(String id) async {
    if (id.isEmpty) return;
    try {
      await widget.api.markNotificationRead(id);
      if (!mounted) return;
      if (_unreadOnly) {
        setState(() {
          _items.removeWhere((item) => item['id']?.toString() == id);
        });
      } else {
        setState(() {
          final index =
              _items.indexWhere((item) => item['id']?.toString() == id);
          if (index >= 0) {
            _items[index] = {..._items[index], 'read': true};
          }
        });
      }
    } catch (e) {
      if (mounted) _showMessage(e.toString());
    }
  }

  Future<void> _markAllRead() async {
    if (_items.isEmpty || _loading) return;
    try {
      await widget.api.markAllNotificationsRead();
      if (!mounted) return;
      if (_unreadOnly) {
        setState(() => _items = const []);
      } else {
        setState(() {
          _items = _items
              .map((item) => {...item, 'read': true})
              .toList(growable: false);
        });
      }
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

  void _setScope(bool unreadOnly) {
    if (_unreadOnly == unreadOnly) return;
    setState(() {
      _unreadOnly = unreadOnly;
      _items = const [];
    });
    load();
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((item) => item['read'] != true).length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NexaPage(
          title: 'Notifications',
          subtitle: _loading
              ? 'Updating your inbox'
              : _error != null
                  ? 'Inbox unavailable'
                  : Format.count(_items.length, 'notification'),
          leading: const NexaBackButton(),
          headerAction: IconButton(
            tooltip: 'Mark all as read',
            onPressed: unread == 0 || _loading ? null : _markAllRead,
            icon: const Icon(Icons.done_all_rounded),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageMargin,
            0,
            AppDimens.pageMargin,
            AppDimens.space24,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NotificationScope(
                unreadOnly: _unreadOnly,
                onChanged: _setScope,
              ),
              const SizedBox(height: AppDimens.space12),
              Expanded(
                child: NexaStateSwitcher(
                  stateKey: ValueKey(_bodyState),
                  child: _loading
                      ? const NexaLoadingBlock()
                      : _error != null
                          ? NexaEmptyState(
                              icon: Icons.cloud_off_rounded,
                              title: 'Notifications unavailable',
                              hint: _error!,
                              actionLabel: 'Try again',
                              onAction: load,
                            )
                          : _items.isEmpty
                              ? NexaEmptyState(
                                  icon: Icons.notifications_none_rounded,
                                  title: _unreadOnly
                                      ? 'You’re all caught up'
                                      : 'No notifications yet',
                                  hint: _unreadOnly
                                      ? 'There are no unread alerts.'
                                      : 'Account and backup activity will appear here.',
                                )
                              : RefreshIndicator(
                                  onRefresh: load,
                                  child: ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    children: [
                                      NexaGroupedList(
                                        header: _unreadOnly
                                            ? 'Unread'
                                            : 'Latest activity',
                                        children: [
                                          for (final item in _items)
                                            _NotificationRow(
                                              item: item,
                                              onMarkRead: () => _markRead(
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
        ),
      ),
    );
  }

  String get _bodyState {
    if (_loading) return 'loading';
    if (_error != null) return 'error';
    return _items.isEmpty ? 'empty:$_unreadOnly' : 'content:$_unreadOnly';
  }
}

/// Material 3 segmented button replaces the former glass pill control.
class _NotificationScope extends StatelessWidget {
  final bool unreadOnly;
  final ValueChanged<bool> onChanged;

  const _NotificationScope({
    required this.unreadOnly,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment<bool>(value: false, label: Text('All activity')),
        ButtonSegment<bool>(value: true, label: Text('Unread')),
      ],
      selected: <bool>{unreadOnly},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onMarkRead;

  const _NotificationRow({
    required this.item,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final read = item['read'] == true;
    final kind = item['kind']?.toString();
    final created = DateTime.tryParse(item['created_at']?.toString() ?? '');
    final message = item['message']?.toString().trim() ?? '';
    final timestamp = Format.relTime(created);
    final subtitle = message.isEmpty ? timestamp : '$message · $timestamp';

    return NexaGroupTile(
      leadingIcon: _icon(kind),
      leadingIconColor:
          read ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
      leadingBackgroundColor:
          read ? scheme.surfaceContainerHigh : scheme.primaryContainer,
      title: item['title']?.toString() ?? 'Notification',
      // Pair the tonal emphasis with explicit state text, never color alone.
      subtitle: read ? subtitle : 'Unread · $subtitle',
      showChevron: false,
      trailing: read
          ? Tooltip(
              message: 'Read',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space12,
                ),
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  size: AppDimens.iconSmall,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          : IconButton(
              tooltip: 'Mark as read',
              onPressed: onMarkRead,
              icon: const Icon(Icons.mark_email_read_outlined),
            ),
    );
  }
}

IconData _icon(String? kind) {
  switch (kind) {
    case 'backup_completed':
      return Icons.backup_rounded;
    case 'backup_restore_ready':
      return Icons.restore_rounded;
    case 'backup_failed':
    case 'backup_restore_failed':
      return Icons.error_outline_rounded;
    default:
      return Icons.notifications_none_rounded;
  }
}
