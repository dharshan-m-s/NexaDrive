import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_typography.dart';
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
      ..showSnackBar(SnackBar(content: Text(message)));
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
    final brightness = Theme.of(context).brightness;
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
          headerAction: NexaLiquidGlass(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            padding: EdgeInsets.zero,
            blurSigma: 12,
            showShadow: false,
            child: IconButton(
              tooltip: 'Mark all as read',
              onPressed: unread == 0 || _loading ? null : _markAllRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
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
                                              brightness: brightness,
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

class _NotificationScope extends StatelessWidget {
  final bool unreadOnly;
  final ValueChanged<bool> onChanged;

  const _NotificationScope({
    required this.unreadOnly,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return NexaLiquidGlass(
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      padding: const EdgeInsets.all(AppDimens.space4),
      blurSigma: 14,
      showShadow: false,
      child: Row(
        children: [
          _ScopeOption(
            label: 'All activity',
            selected: !unreadOnly,
            onTap: () => onChanged(false),
          ),
          _ScopeOption(
            label: 'Unread',
            selected: unreadOnly,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ScopeOption({
    required this.label,
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
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: AnimatedContainer(
              duration: AppMotion.resolve(context, AppMotion.fast),
              curve: AppMotion.standardCurve,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space12,
                vertical: AppDimens.space10,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.glassSelectionFor(brightness)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                border: selected
                    ? Border.all(
                        color: AppColors.glassBorderFor(brightness),
                        width: 0.7,
                      )
                    : null,
              ),
              child: Text(
                label,
                style: AppTextStyle.caption1.copyWith(
                  color: selected
                      ? AppColors.labelPrimaryFor(brightness)
                      : AppColors.labelSecondaryFor(brightness),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final Brightness brightness;
  final VoidCallback onMarkRead;

  const _NotificationRow({
    required this.item,
    required this.brightness,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final read = item['read'] == true;
    final kind = item['kind']?.toString();
    final created = DateTime.tryParse(item['created_at']?.toString() ?? '');
    final message = item['message']?.toString().trim() ?? '';
    final timestamp = Format.relTime(created);
    final subtitle = message.isEmpty ? timestamp : '$message · $timestamp';

    return NexaGroupTile(
      leadingIcon: _icon(kind),
      leadingIconColor: read
          ? AppColors.labelSecondaryFor(brightness)
          : AppColors.accentTextFor(brightness),
      leadingBackgroundColor: read
          ? AppColors.fillFor(brightness)
          : AppColors.accentContainerFor(brightness),
      title: item['title']?.toString() ?? 'Notification',
      subtitle: subtitle,
      showChevron: false,
      trailing: read
          ? null
          : IconButton(
              tooltip: 'Mark as read',
              onPressed: onMarkRead,
              icon: Icon(
                Icons.mark_email_read_outlined,
                color: AppColors.accentTextFor(brightness),
              ),
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
