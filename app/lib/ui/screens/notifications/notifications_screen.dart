import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/one_ui_controls.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_page.dart';
import '../../widgets/one_ui_surface.dart';

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

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.api.notifications(unreadOnly: _unreadOnly);
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

  Future<void> _markRead(String id) async {
    try {
      await widget.api.markNotificationRead(id);
      await load();
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await widget.api.markAllNotificationsRead();
      await load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: OneUiPage(
          title: 'Notifications',
          subtitle: _unreadOnly
              ? 'Unread only'
              : '${_items.length} item${_items.length == 1 ? '' : 's'}',
          leading: const OneUiBackButton(),
          headerAction: IconButton(
            tooltip: 'Mark all read',
            onPressed: _markAllRead,
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
              Padding(
                padding: const EdgeInsets.only(bottom: AppDimens.space12),
                child: Row(
                  children: [
                    Text('Filter',
                        style: AppTextStyle.rowSubtitle.copyWith(
                            color: AppColors.textSecondaryFor(brightness))),
                    const SizedBox(width: AppDimens.space12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('All')),
                        ButtonSegment(value: true, label: Text('Unread')),
                      ],
                      selected: {_unreadOnly},
                      onSelectionChanged: (v) {
                        setState(() => _unreadOnly = v.first);
                        load();
                      },
                      showSelectedIcon: false,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const OneUiLoadingBlock()
                    : _items.isEmpty
                        ? const OneUiEmptyState(
                            icon: Icons.notifications_none_rounded,
                            title: 'No notifications',
                            hint:
                                'Backup and account alerts will show up here.',
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppDimens.space2),
                            itemBuilder: (context, i) => _NotificationCard(
                              item: _items[i],
                              brightness: brightness,
                              onMarkRead: () =>
                                  _markRead(_items[i]['id'] as String),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One notification as a standard One UI surface row.
///
/// Unread items keep the accent container fill and a semibold title, so
/// read/unread stays legible without adding a separate badge.
class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Brightness brightness;
  final VoidCallback onMarkRead;

  const _NotificationCard({
    required this.item,
    required this.brightness,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final read = item['read'] == true;
    final kind = item['kind']?.toString();
    final unreadSurface = brightness == Brightness.dark
        ? AppColors.surfaceAltDark
        : AppColors.accentContainerLight;
    final readSurface = brightness == Brightness.dark
        ? AppColors.surfaceDark
        : AppColors.surfaceLight;

    return OneUiSurface(
      level: OneUiSurfaceLevel.surface,
      radius: AppDimens.radiusTile,
      color: read ? readSurface : unreadSurface,
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusTile),
          ),
          leading: Icon(
            _icon(kind),
            color: read
                ? AppColors.textTertiaryFor(brightness)
                : AppColors.accentFor(brightness),
          ),
          title: Text(
            item['title']?.toString() ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.rowTitle.copyWith(
              color: AppColors.textPrimaryFor(brightness),
              fontWeight: read ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${item['message']?.toString() ?? ''} · '
            '${Format.relTime(DateTime.tryParse(item['created_at']?.toString() ?? ''))}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption.copyWith(
              color: AppColors.textSecondaryFor(brightness),
            ),
          ),
          trailing: read
              ? null
              : IconButton(
                  tooltip: 'Mark read',
                  icon: Icon(
                    Icons.mark_email_read_outlined,
                    color: AppColors.accentFor(brightness),
                  ),
                  onPressed: onMarkRead,
                ),
        ),
      ),
    );
  }
}

/// Maps a notification kind to its leading glyph.
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
