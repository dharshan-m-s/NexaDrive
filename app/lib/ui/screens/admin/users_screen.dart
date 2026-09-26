import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../../services/session.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_page.dart';
import 'admin_user_rules.dart';
import 'user_sheets.dart';
import 'users_controller.dart';

/// Users administration, rebuilt from scratch.
///
/// Architecture: the page renders [UsersController] state. All account
/// mutations go through the controller; the UI owns presentation only.
///
/// Presentation contract: one editing surface (a One UI bottom sheet on every
/// platform), one actions surface (a bottom-sheet menu), explicit text styles
/// everywhere, and no text that inherits a decoration.
class UsersScreen extends StatefulWidget {
  final Api api;
  const UsersScreen({super.key, required this.api});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late final UsersController _controller = UsersController(widget.api);

  @override
  void initState() {
    super.initState();
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return OneUiPage(
          title: 'Users',
          subtitle: 'Manage accounts and access',
          headerAction: IconButton(
            tooltip: 'Add user',
            onPressed: () => _showCreateSheet(context),
            icon: const Icon(Icons.person_add_alt_rounded),
          ),
          body: switch (c.loadState) {
            UsersLoadState.loading => _buildLoading(),
            UsersLoadState.failure => _buildFailure(c),
            UsersLoadState.ready when c.users.isEmpty => _buildEmpty(context),
            UsersLoadState.ready => _buildList(c),
          },
        );
      },
    );
  }

  Widget _buildLoading() {
    return ListView(
      children: const [
        SizedBox(height: 96),
        Center(
          child: Column(
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: AppDimens.space16),
              Text('Loading accounts…'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFailure(UsersController c) {
    final (title, hint) = _failureInfo(c.error);
    return OneUiEmptyState(
      icon: Icons.error_outline_rounded,
      title: title,
      hint: hint,
      actionLabel: 'Retry',
      actionIcon: Icons.refresh_rounded,
      onAction: c.refresh,
      centered: true,
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ListView(
      padding: const EdgeInsets.only(bottom: AppDimens.space24),
      children: [
        const _SummaryStrip(
            summary: UserSummary(total: 0, admins: 0, blocked: 0)),
        const SizedBox(height: AppDimens.space8),
        Container(
          padding: const EdgeInsets.all(AppDimens.space16),
          decoration: BoxDecoration(
            color: AppColors.surfaceFor(Theme.of(context).brightness),
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          ),
          child: Row(
            children: [
              Icon(
                Icons.people_outline_rounded,
                color: AppColors.accentFor(brightness),
                size: AppDimens.iconMedium,
              ),
              const SizedBox(width: AppDimens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No accounts yet',
                      style: AppTextStyle.rowTitle.copyWith(
                        color: AppColors.textPrimaryFor(brightness),
                      ),
                    ),
                    const SizedBox(height: AppDimens.space2),
                    Text(
                      'Add the first account to let people in.',
                      style: AppTextStyle.caption.copyWith(
                        color: AppColors.textSecondaryFor(brightness),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => _showCreateSheet(context),
                child: const Text('Add user'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList(UsersController c) {
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppDimens.space24),
        children: [
          SearchBar(
            hintText: 'Search accounts',
            leading: const Icon(Icons.search_rounded),
            elevation: const WidgetStatePropertyAll(0),
            constraints: const BoxConstraints(minHeight: 48),
            onChanged: c.setQuery,
          ),
          const SizedBox(height: AppDimens.space8),
          if (c.visible.isEmpty)
            OneUiEmptyState(
              icon: Icons.search_off_rounded,
              title: 'No accounts match "${c.query}"',
              hint: 'Clear the search to see all accounts.',
              actionLabel: 'Clear search',
              onAction: () => c.setQuery(''),
            )
          else ...[
            _SummaryStrip(summary: c.summary),
            const SizedBox(height: AppDimens.space8),
            for (final user in c.visible)
              _UserRow(
                user: user,
                session: c.session,
                isAdminSelf: user.isAdmin && user.isSelf(c.session),
                onOpen: () => _showEditSheet(context, user),
                onActions: () => _showActionsSheet(context, user),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _showCreateSheet(BuildContext context) async {
    final created = await showUserEditorSheet(
      context,
      title: 'New account',
      onSave: ({
        required username,
        required displayName,
        required password,
        required role,
        required quotaBytes,
        bool clearQuota = false,
        bool disabled = false,
      }) async {
        return _controller.createAccount(
          username: username,
          displayName: displayName,
          password: password,
          role: role,
          quotaBytes: quotaBytes,
        );
      },
    );
    if (created == true && mounted) _toast('Account created');
  }

  Future<void> _showEditSheet(BuildContext context, UserProfile user) async {
    final saved = await showUserEditorSheet(
      context,
      title: 'Edit account',
      existing: user,
      usernameLocked: true,
      onSave: ({
        required username,
        required displayName,
        required password,
        required role,
        required quotaBytes,
        bool clearQuota = false,
        bool disabled = false,
      }) async {
        final error = await _controller.updateAccount(
          user.id,
          displayName: displayName,
          role: role,
          disabled: disabled,
          quotaBytes: quotaBytes,
          clearQuota: clearQuota,
          password: password.isEmpty ? null : password,
        );
        if (error == null && password.isNotEmpty && mounted) {
          _toast(
              'Password changed — that user has been signed out everywhere.');
        }
        return error;
      },
    );
    if (saved == true && mounted) _toast('Account updated');
  }

  Future<void> _showActionsSheet(BuildContext context, UserProfile user) async {
    final blocker = AdminUserRules.deletionBlocker(
      _controller.session,
      _controller.users.map(_toRaw).toList(),
      _toRaw(user),
    );
    await showUserActionsSheet(
      context,
      user: user,
      protectedReason: blocker,
      onEdit: () => _showEditSheet(context, user),
      onToggleBlock: () async {
        final error = await _controller.updateAccount(
          user.id,
          disabled: !user.disabled,
        );
        if (mounted) {
          _toast(error ??
              (user.disabled ? 'Account unblocked' : 'Account blocked'));
        }
      },
      onDelete: () => _confirmDelete(context, user),
    );
  }

  Future<void> _confirmDelete(BuildContext context, UserProfile user) async {
    final name =
        user.displayName.trim().isNotEmpty ? user.displayName : user.username;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $name?'),
        content: Text(
          'Delete "@${user.username}"? This permanently removes their '
          'files, shares, trash and session, and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.errorFor(Theme.of(context).brightness),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final error = await _controller.deleteAccount(user.id);
    if (!mounted) return;
    _toast(error ?? 'Deleted $name');
  }

  static Map<String, dynamic> _toRaw(UserProfile u) => {
        'id': u.id,
        'username': u.username,
        'display_name': u.displayName,
        'role': u.isAdmin ? 'admin' : 'user',
        'disabled': u.disabled,
        'quota_bytes': u.quotaBytes,
      };

  (String, String) _failureInfo(Object? error) {
    if (error is ApiException) {
      switch (error.status) {
        case 401:
          return ('Your session expired', 'Sign in again to continue.');
        case 403:
          return (
            'Administrator access required',
            'You need administrator access to manage accounts.',
          );
        default:
          if (error.status >= 500) {
            return ('The server couldn\u2019t load accounts', error.message);
          }
          return ('Couldn\u2019t load accounts', error.message);
      }
    }
    return (
      'Can\u2019t reach the server',
      'Check your connection and that the server is on this network.',
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Compact role summary strip: accounts / administrators / blocked.
class _SummaryStrip extends StatelessWidget {
  final UserSummary summary;
  const _SummaryStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            icon: Icons.people_outline_rounded,
            color: AppColors.accentFor(brightness),
            label: plural(summary.total, 'account'),
          ),
        ),
        const SizedBox(width: AppDimens.space8),
        Expanded(
          child: _SummaryTile(
            icon: Icons.admin_panel_settings_outlined,
            color: AppColors.accentTextFor(brightness),
            label: plural(summary.admins, 'administrator'),
          ),
        ),
        const SizedBox(width: AppDimens.space8),
        Expanded(
          child: _SummaryTile(
            icon: Icons.block_rounded,
            color: AppColors.warningFor(brightness),
            label: plural(summary.blocked, 'blocked'),
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _SummaryTile({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12,
        vertical: AppDimens.space10,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceFor(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(AppDimens.radiusTile),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppDimens.space8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption.copyWith(
                color: AppColors.textPrimaryFor(Theme.of(context).brightness),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One account row: avatar, identity, chips, and the actions affordance.
class _UserRow extends StatelessWidget {
  final UserProfile user;
  final Session session;
  final bool isAdminSelf;
  final VoidCallback onOpen;
  final VoidCallback onActions;

  const _UserRow({
    required this.user,
    required this.session,
    required this.isAdminSelf,
    required this.onOpen,
    required this.onActions,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final disabled = user.disabled;

    final metaParts = <String>[
      '@${user.username}',
      if (user.quotaBytes != null)
        '${(user.quotaBytes! / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB'
      else
        'Unlimited storage',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.space8),
      child: Material(
        color: AppColors.surfaceFor(brightness),
        borderRadius: BorderRadius.circular(AppDimens.radiusTile),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDimens.radiusTile),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.space12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: AppDimens.iconTile / 2,
                  backgroundColor: disabled
                      ? AppColors.surfaceAltLight
                      : accent.withValues(alpha: 0.14),
                  foregroundColor:
                      disabled ? AppColors.textTertiaryFor(brightness) : accent,
                  child: Text(
                    _initial(user.displayName),
                    style: AppTextStyle.buttonSmall,
                  ),
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.rowTitle.copyWith(
                                color: AppColors.textPrimaryFor(brightness),
                              ),
                            ),
                          ),
                          if (user.isAdmin) ...[
                            const SizedBox(width: AppDimens.space6),
                            _Chip(
                              label: 'Admin',
                              foreground: AppColors.accentTextFor(brightness),
                              background: accent.withValues(alpha: 0.12),
                            ),
                          ],
                          if (isAdminSelf) ...[
                            const SizedBox(width: AppDimens.space6),
                            _Chip(
                              label: 'You',
                              foreground: AppColors.successFor(brightness),
                              background: AppColors.successFor(brightness)
                                  .withValues(alpha: 0.14),
                            ),
                          ],
                          if (disabled) ...[
                            const SizedBox(width: AppDimens.space6),
                            _Chip(
                              label: 'Blocked',
                              foreground: AppColors.errorFor(brightness),
                              background: AppColors.errorFor(brightness)
                                  .withValues(alpha: 0.12),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppDimens.space2),
                      Text(
                        metaParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.caption.copyWith(
                          color: AppColors.textSecondaryFor(brightness),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.space8),
                IconButton(
                  tooltip: 'Account actions',
                  onPressed: onActions,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: AppColors.textSecondaryFor(brightness),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;

  const _Chip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Text(
        label,
        style: AppTextStyle.micro.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
