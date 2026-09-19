import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../../services/session.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_grouped_list.dart';
import '../../widgets/one_ui_page.dart';
import 'admin_user_rules.dart';

/// Administrator account management: a searchable list of accounts with an
/// editor, role/block toggles, and deletion — all guarded by the same rules
/// the server enforces ([AdminUserRules]).
class AdminUsersScreen extends StatefulWidget {
  final Api api;
  const AdminUsersScreen({super.key, required this.api});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  Object? _error;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  static const double _gib = 1024 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await widget.api.users();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  List<Map<String, dynamic>> get _visible =>
      AdminUserRules.filter(_users, _query);

  @override
  Widget build(BuildContext context) {
    return OneUiPage(
      title: 'Users',
      subtitle: 'Manage accounts and access',
      headerAction: IconButton(
        tooltip: 'Add user',
        onPressed: _createUser,
        icon: const Icon(Icons.person_add_alt_rounded),
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: AppDimens.space16),
            Text('Loading accounts…'),
          ],
        ),
      );
    }
    if (_error != null) {
      return _ErrorPanel(error: _error!, onRetry: load);
    }
    if (_users.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: AppDimens.space24),
        children: [
          OneUiGroupedList(
            header: 'Accounts',
            withDividers: false,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.space16,
                  AppDimens.space12,
                  AppDimens.space12,
                  AppDimens.space12,
                ),
                child: Row(
                  children: [
                    _AvatarTile(
                      icon: Icons.people_outline_rounded,
                      color: AppColors.accentFor(Theme.of(context).brightness),
                    ),
                    const SizedBox(width: AppDimens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No accounts yet',
                            style: AppTextStyle.rowTitle.copyWith(
                              color: AppColors.textPrimaryFor(
                                  Theme.of(context).brightness),
                            ),
                          ),
                          const SizedBox(height: AppDimens.space2),
                          Text(
                            'Add the first account to let people in.',
                            style: AppTextStyle.caption.copyWith(
                              color: AppColors.textSecondaryFor(
                                  Theme.of(context).brightness),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppDimens.space12),
                    FilledButton(
                      onPressed: _createUser,
                      child: const Text('Add user'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _rolesGroup(const []),
        ],
      );
    }

    final visible = _visible;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppDimens.space24),
        children: [
          SearchBar(
            controller: _search,
            hintText: 'Search accounts',
            leading: const Icon(Icons.search_rounded),
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(
              Theme.of(context).brightness == Brightness.dark
                  ? AppColors.surfaceAltDark
                  : AppColors.surfaceAltLight,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: AppDimens.space8),
          if (visible.isEmpty)
            OneUiEmptyState(
              icon: Icons.search_off_rounded,
              title: 'No accounts match "$_query"',
              hint: 'Clear the search to see all accounts.',
              actionLabel: 'Clear search',
              onAction: () {
                _search.clear();
                setState(() => _query = '');
              },
            )
          else ...[
            _rolesGroup(visible),
            _accountsGroup(visible),
          ],
        ],
      ),
    );
  }

  /// Role breakdown: total, administrators, blocked. Derived from the visible
  /// list so a narrowed search never shows stale totals.
  Widget _rolesGroup(List<Map<String, dynamic>> source) {
    final brightness = Theme.of(context).brightness;
    final total = source.length;
    final admins = source.where(AdminUserRules.isAdmin).length;
    final blocked = source.where(AdminUserRules.isDisabled).length;

    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

    return OneUiGroupedList(
      header: 'Roles',
      withDividers: true,
      children: [
        _RoleCount(
          label: plural(total, 'account'),
          icon: Icons.people_outline_rounded,
          color: AppColors.accentFor(brightness),
        ),
        _RoleCount(
          label: plural(admins, 'administrator'),
          icon: Icons.admin_panel_settings_outlined,
          color: AppColors.accentTextFor(brightness),
        ),
        _RoleCount(
          label: plural(blocked, 'blocked'),
          icon: Icons.block_rounded,
          color: AppColors.warningFor(brightness),
        ),
      ],
    );
  }

  Widget _accountsGroup(List<Map<String, dynamic>> visible) {
    return OneUiGroupedList(
      header: 'Accounts',
      withDividers: true,
      children: [
        for (final user in visible)
          _UserTile(
            user: user,
            session: widget.api.session,
            users: _users,
            onEdit: () => _editUser(user),
            onDelete: () => _requestDelete(user),
            onToggleBlock: () => _toggleBlock(user),
          ),
      ],
    );
  }

  Future<void> _createUser() async {
    final username = TextEditingController();
    final displayName = TextEditingController();
    final password = TextEditingController();
    final quota = TextEditingController();
    String role = 'user';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: username,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: AppDimens.space12),
                TextField(
                  controller: displayName,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: AppDimens.space12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 10 characters',
                  ),
                ),
                const SizedBox(height: AppDimens.space12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('User')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (v) => setDialogState(() => role = v!),
                  decoration: const InputDecoration(labelText: 'Role'),
                ),
                const SizedBox(height: AppDimens.space12),
                TextField(
                  controller: quota,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Quota (GB, optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (password.text.trim().length < 10) {
      _toast('Password must be at least 10 characters');
      return;
    }
    try {
      final raw = quota.text.trim();
      int? quotaBytes;
      if (raw.isNotEmpty) {
        final gb = double.tryParse(raw);
        if (gb != null && gb > 0) {
          quotaBytes = (gb * _gib).round();
        }
      }
      await widget.api.createUser(
        username: username.text.trim(),
        displayName: displayName.text.trim(),
        password: password.text,
        role: role,
        quotaBytes: quotaBytes,
      );
      await load();
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final brightness = Theme.of(context).brightness;
    final displayName = TextEditingController(
      text: user['display_name']?.toString() ?? '',
    );
    final password = TextEditingController();
    final quota = TextEditingController(
      text: _quotaLabel(user['quota_bytes'] as num?),
    );
    final username = user['username']?.toString() ?? '';
    String role = user['role'] == 'admin' ? 'admin' : 'user';
    var disabled = user['disabled'] == true;
    String? validationError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: displayName,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: AppDimens.space12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('User')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (v) => setDialogState(() => role = v!),
                  decoration: const InputDecoration(labelText: 'Role'),
                ),
                const SizedBox(height: AppDimens.space12),
                TextField(
                  controller: quota,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quota (GB, empty = unlimited)',
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Block account',
                      style: AppTextStyle.rowTitle),
                  subtitle: const Text('Prevents this user from '
                      'logging in without deleting their files.'),
                  value: disabled,
                  onChanged: (v) => setDialogState(() => disabled = v),
                ),
                const SizedBox(height: AppDimens.space8),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password (optional)',
                    helperText: 'Leave empty to keep the current password. '
                        'Changing it signs this user out everywhere.',
                  ),
                ),
                const SizedBox(height: AppDimens.space12),
                Row(
                  children: [
                    Text(
                      'Username',
                      style: AppTextStyle.caption.copyWith(
                        color: AppColors.textSecondaryFor(brightness),
                      ),
                    ),
                    const SizedBox(width: AppDimens.space8),
                    Expanded(
                      child: Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.rowSubtitle.copyWith(
                          color: AppColors.textPrimaryFor(brightness),
                        ),
                      ),
                    ),
                  ],
                ),
                if (validationError != null) ...[
                  const SizedBox(height: AppDimens.space12),
                  Text(
                    validationError!,
                    style: AppTextStyle.caption.copyWith(
                      color: AppColors.errorFor(brightness),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => setDialogState(() {
                validationError =
                    _validateEdit(displayName.text, password.text);
                if (validationError == null) {
                  Navigator.pop(context, true);
                }
              }),
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
      barrierDismissible: false,
    );
    if (ok != true) return;
    if (validationError != null) {
      _toast(validationError!);
      return;
    }
    try {
      final raw = quota.text.trim();
      final quotaEmpty = raw.isEmpty;
      int? quotaBytes;
      if (!quotaEmpty) {
        final gb = double.tryParse(raw);
        if (gb == null) {
          _toast('Quota must be a number in GB, or leave it empty');
          return;
        }
        if (gb > 0) quotaBytes = (gb * _gib).round();
      }
      await widget.api.updateUser(
        user['id'] as String,
        displayName: displayName.text.trim(),
        role: role,
        quotaBytes: quotaBytes,
        clearQuota: quotaEmpty,
        disabled: disabled,
        password: password.text.isEmpty ? null : password.text,
      );
      await load();
      if (password.text.isNotEmpty && mounted) {
        _toast('Password changed — that user has been signed out everywhere.');
      }
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  String? _validateEdit(String displayName, String password) {
    if (displayName.trim().isEmpty) return 'Enter a display name';
    if (password.isNotEmpty && password.length < 10) {
      return 'Password must be at least 10 characters';
    }
    return null;
  }

  Future<void> _toggleBlock(Map<String, dynamic> user) async {
    final blocker =
        AdminUserRules.demotionBlocker(widget.api.session, _users, user);
    if (blocker != null) {
      await _showProtected(blocker);
      return;
    }
    try {
      await widget.api.updateUser(
        user['id'] as String,
        disabled: user['disabled'] != true,
      );
      await load();
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _requestDelete(Map<String, dynamic> user) async {
    final blocker =
        AdminUserRules.deletionBlocker(widget.api.session, _users, user);
    if (blocker != null) {
      await _showProtected(blocker);
      return;
    }
    final name = user['display_name']?.toString().trim().isNotEmpty == true
        ? user['display_name']!.toString()
        : user['username']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final brightness = Theme.of(context).brightness;
        return AlertDialog(
          title: Text('Delete $name?'),
          content: Text(
            'Delete "@$username"? This permanently removes their '
            'files, shares, trash and session, and cannot be undone.',
            style: const TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.errorFor(brightness),
                foregroundColor: AppColors.textOnPrimaryLight,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete account'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    try {
      await widget.api.deleteUser(user['id'] as String);
      if (!mounted) return;
      _toast('Deleted $name');
      await load();
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _showProtected(String reason) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This account is protected'),
        content: Text(reason, style: const TextStyle(height: 1.4)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// "12" GB → "12", "12.5" → "12.5", null → "" — round-trips the quota
  /// field in the editor and the "25 GB" row metadata.
  static String _quotaLabel(num? quotaBytes) {
    if (quotaBytes == null) return '';
    final gb = quotaBytes / _gib;
    return gb == gb.roundToDouble() ? gb.toStringAsFixed(0) : gb.toStringAsFixed(1);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RoleCount extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _RoleCount({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16, vertical: AppDimens.space10,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppDimens.radiusInner),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: AppDimens.space12),
          Text(
            label,
            style: AppTextStyle.rowTitle.copyWith(
              color: AppColors.textPrimaryFor(Theme.of(context).brightness),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _AvatarTile({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppDimens.iconTile,
      height: AppDimens.iconTile,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimens.radiusInner),
      ),
      child: Icon(icon, size: AppDimens.iconSmall, color: color),
    );
  }
}

/// One One UI account row: avatar, name, meta (`@username · role · quota`),
/// status chips, and the account action menu.
class _UserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final Session session;
  final List<Map<String, dynamic>> users;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleBlock;

  const _UserTile({
    required this.user,
    required this.session,
    required this.users,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleBlock,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final disabled = user['disabled'] == true;
    final isAdmin = AdminUserRules.isAdmin(user);
    final isSelf = AdminUserRules.isSelf(session, user);
    final accent = AppColors.accentFor(brightness);
    final quotaBytes = (user['quota_bytes'] as num?)?.toInt();
    final displayName =
        user['display_name']?.toString().trim().isNotEmpty == true
            ? user['display_name']!.toString()
            : user['username']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';

    final metaParts = <String>[
      '@$username',
      if (isAdmin) 'Admin',
      if (quotaBytes != null)
        '${(quotaBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB'
      else
        'Unlimited storage',
    ];
    final meta = metaParts.join(' · ');

    return OneUiGroupTile(
      enabled: !disabled,
      leading: CircleAvatar(
        radius: AppDimens.iconTile / 2,
        backgroundColor: disabled
            ? AppColors.surfaceAltLight
            : accent.withValues(alpha: 0.14),
        foregroundColor: disabled
            ? AppColors.textTertiaryFor(brightness)
            : accent,
        child: Text(
          _initial(displayName),
          style: AppTextStyle.buttonSmall,
        ),
      ),
      title: displayName,
      subtitle: disabled ? 'Blocked · $meta' : meta,
      showChevron: false,
      onTap: onEdit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isAdmin)
            _RoleChip(
              label: 'Admin',
              background: accent.withValues(alpha: 0.12),
              foreground: AppColors.accentTextFor(brightness),
            ),
          if (disabled)
            _RoleChip(
              label: 'Blocked',
              background: AppColors.errorFor(brightness).withValues(alpha: 0.12),
              foreground: AppColors.errorFor(brightness),
            ),
          if (isSelf)
            _RoleChip(
              label: 'You',
              background: AppColors.successFor(brightness).withValues(alpha: 0.14),
              foreground: AppColors.successFor(brightness),
            ),
          PopupMenuButton<String>(
            tooltip: 'Account actions',
            icon: Icon(
              Icons.more_vert_rounded,
              color: AppColors.textSecondaryFor(brightness),
            ),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                case 'delete':
                  onDelete();
                case 'block':
                  onToggleBlock();
              }
            },
            itemBuilder: (context) => [
              ..._protectionNote(context),
              const PopupMenuItem(value: 'edit', child: Text('Edit account')),
              PopupMenuItem(
                value: 'block',
                child: Text(disabled ? 'Unblock account' : 'Block account'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete account'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _protectionNote(BuildContext context) {
    final blocker = AdminUserRules.deletionBlocker(session, users, user);
    if (blocker == null) return const [];
    return [
      PopupMenuItem(
        enabled: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.space4),
          child: Text(
            blocker,
            style: AppTextStyle.caption.copyWith(
              color: AppColors.textSecondaryFor(Theme.of(context).brightness),
            ),
          ),
        ),
      ),
    ];
  }

  String _initial(String name) {
    final letter = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return letter;
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  const _RoleChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: AppDimens.space6),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space8, vertical: AppDimens.space4,
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

/// Distinguishes the four failure modes so each is explained in plain
/// language and offers the same way out (Retry).
class _ErrorPanel extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;
  const _ErrorPanel({required this.error, required this.onRetry});

  (String, String) _info() {
    if (error is ApiException) {
      final status = (error as ApiException).status;
      switch (status) {
        case 401:
          return ('Your session expired', 'Sign in again to continue.');
        case 403:
          return ('Administrator access required',
              'You need administrator access to manage accounts.');
        default:
          if (status >= 500) {
            return ('The server couldn’t load accounts',
                (error as ApiException).message);
          }
          return ('Couldn’t load accounts', (error as ApiException).message);
      }
    }
    return ('Can’t reach the server',
        'Check your connection and that the server is on this network.');
  }

  @override
  Widget build(BuildContext context) {
    final (title, hint) = _info();
    return OneUiEmptyState(
      icon: Icons.error_outline_rounded,
      title: title,
      hint: hint,
      actionLabel: 'Retry',
      actionIcon: Icons.refresh_rounded,
      onAction: onRetry,
      centered: true,
    );
  }
}