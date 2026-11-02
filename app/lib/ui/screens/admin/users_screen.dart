import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../../services/session.dart';
import '../../widgets/nexa_components.dart';
import 'admin_user_rules.dart';
import 'user_sheets.dart';
import 'users_controller.dart';

/// Users administration — an iOS-style grouped account list.
///
/// Architecture: the page renders [UsersController] state. All account
/// mutations go through the controller; the UI owns presentation only.
///
/// Presentation contract: one editing surface (a bottom sheet on every
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
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return NexaPage(
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
        NexaLoadingBlock(label: 'Loading accounts…'),
      ],
    );
  }

  Widget _buildFailure(UsersController c) {
    final (title, hint) = _failureInfo(c.error);
    return NexaEmptyState(
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
      padding: const EdgeInsets.only(top: AppDimens.space8),
      children: [
        NexaSurface(
          padding: const EdgeInsets.all(AppDimens.space16),
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
                        color: AppColors.labelPrimaryFor(brightness),
                      ),
                    ),
                    const SizedBox(height: AppDimens.space2),
                    Text(
                      'Add the first account to let people in.',
                      style: AppTextStyle.caption.copyWith(
                        color: AppColors.labelSecondaryFor(brightness),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.space12),
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
          Padding(
            padding: const EdgeInsets.only(bottom: AppDimens.space12),
            child: NexaSearchField(
              controller: _search,
              hint: 'Search accounts',
              onChanged: c.setQuery,
              onClear: () {
                _search.clear();
                c.setQuery('');
              },
            ),
          ),
          if (c.visible.isEmpty)
            NexaEmptyState(
              icon: Icons.search_off_rounded,
              title: 'No accounts match "${c.query}"',
              hint: 'Clear the search to see all accounts.',
              actionLabel: 'Clear search',
              onAction: () {
                _search.clear();
                c.setQuery('');
              },
            )
          else ...[
            _SummaryStrip(summary: c.summary),
            const SizedBox(height: AppDimens.space16),
            NexaSectionHeader('Accounts'),
            NexaGroupedList(
              withDividers: false,
              children: [
                for (var i = 0; i < c.visible.length; i++) ...[
                  _UserRow(
                    user: c.visible[i],
                    session: c.session,
                    isAdminSelf:
                        c.visible[i].isAdmin && c.visible[i].isSelf(c.session),
                    onOpen: () => _showEditSheet(context, c.visible[i]),
                    onActions: () => _showActionsSheet(context, c.visible[i]),
                  ),
                  if (i < c.visible.length - 1) const NexaDivider.inset(),
                ],
              ],
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

/// Compact role summary: accounts / administrators / blocked, in one surface
/// separated by hairlines rather than three competing cards.
class _SummaryStrip extends StatelessWidget {
  final UserSummary summary;
  const _SummaryStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

    Widget cell(IconData icon, Color color, String label) => Expanded(
          child: Row(
            children: [
              Icon(icon, size: AppDimens.iconSmall, color: color),
              const SizedBox(width: AppDimens.space8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption.copyWith(
                    color: AppColors.labelPrimaryFor(brightness),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12,
        vertical: AppDimens.space12,
      ),
      child: Row(
        children: [
          cell(
            Icons.people_outline_rounded,
            AppColors.accentFor(brightness),
            plural(summary.total, 'account'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppDimens.space8),
            child: NexaVerticalDivider(height: 20),
          ),
          cell(
            Icons.admin_panel_settings_outlined,
            AppColors.accentTextFor(brightness),
            plural(summary.admins, 'administrator'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppDimens.space8),
            child: NexaVerticalDivider(height: 20),
          ),
          cell(
            Icons.block_rounded,
            AppColors.warningFor(brightness),
            plural(summary.blocked, 'blocked'),
          ),
        ],
      ),
    );
  }
}

/// One account row: avatar, identity with status chips, storage subtitle, and
/// the actions affordance. Inside the grouped panel this reads as a single
/// iOS Settings-style row.
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

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.pageMargin,
            vertical: AppDimens.space12,
          ),
          child: Row(
            children: [
              NexaAvatar(
                name: user.displayName,
                radius: AppDimens.iconTileLarge / 2,
                backgroundColor: disabled
                    ? AppColors.fillFor(brightness)
                    : accent.withValues(alpha: 0.14),
                foregroundColor:
                    disabled ? AppColors.labelTertiaryFor(brightness) : accent,
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
                              color: disabled
                                  ? AppColors.labelTertiaryFor(brightness)
                                  : AppColors.labelPrimaryFor(brightness),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (user.isAdmin) ...[
                          const SizedBox(width: AppDimens.space6),
                          NexaChip.filled(label: 'Admin'),
                        ],
                        if (isAdminSelf) ...[
                          const SizedBox(width: AppDimens.space6),
                          NexaChip.tonal(
                            label: 'You',
                            tintColor:
                                AppColors.successContainerFor(brightness),
                            tintForeground:
                                AppColors.onSuccessContainerFor(brightness),
                          ),
                        ],
                        if (disabled) ...[
                          const SizedBox(width: AppDimens.space6),
                          NexaChip.tonal(
                            label: 'Blocked',
                            tintColor: AppColors.errorContainerFor(brightness),
                            tintForeground:
                                AppColors.onErrorContainerFor(brightness),
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
                        color: AppColors.labelSecondaryFor(brightness),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Account actions',
                onPressed: onActions,
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.labelSecondaryFor(brightness),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
