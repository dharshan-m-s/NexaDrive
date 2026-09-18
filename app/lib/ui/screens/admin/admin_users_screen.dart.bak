import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_grouped_list.dart';
import '../../widgets/one_ui_page.dart';

class AdminUsersScreen extends StatefulWidget {
  final Api api;
  const AdminUsersScreen({super.key, required this.api});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => _loading = true);
    try {
      final users = await widget.api.users();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(e.toString());
    }
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
          title: const Text('New user'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: username,
                    decoration: const InputDecoration(labelText: 'Username')),
                const SizedBox(height: AppDimens.space12),
                TextField(controller: displayName,
                    decoration: const InputDecoration(labelText: 'Display name')),
                const SizedBox(height: AppDimens.space12),
                TextField(controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      helperText: 'At least 10 characters',
                    )),
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
                  decoration: const InputDecoration(labelText: 'Quota (GB, optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
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
          quotaBytes = (gb * 1024 * 1024 * 1024).round();
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
    final displayName = TextEditingController(
      text: user['display_name']?.toString() ?? '',
    );
    final password = TextEditingController();
    final quota = TextEditingController(
      text: _quotaLabel(user['quota_bytes'] as num?),
    );
    String role = user['role'] == 'admin' ? 'admin' : 'user';
    var disabled = user['disabled'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit user'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: displayName,
                    decoration: const InputDecoration(labelText: 'Display name')),
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
                  decoration: const InputDecoration(labelText: 'Quota (GB, empty = unlimited)'),
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
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (displayName.text.trim().isEmpty) {
      _toast('Display name cannot be empty');
      return;
    }
    if (password.text.isNotEmpty && password.text.length < 10) {
      _toast('Password must be at least 10 characters');
      return;
    }
    try {
      final raw = quota.text.trim();
      if (raw.isNotEmpty && double.tryParse(raw) == null) {
        _toast('Quota must be a number in GB, or leave it empty');
        return;
      }
      int? quotaBytes;
      if (raw.isNotEmpty) {
        final gb = double.parse(raw);
        if (gb > 0) quotaBytes = (gb * 1024 * 1024 * 1024).round();
      }
      await widget.api.updateUser(
        user['id'] as String,
        displayName: displayName.text.trim(),
        role: role,
        quotaBytes: quotaBytes,
        disabled: disabled,
        password: password.text,
      );
      await load();
      if (password.text.isNotEmpty && mounted) {
        _toast('Password changed — that user has been signed out everywhere.');
      }
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final name = user['display_name']?.toString() ?? user['username']?.toString() ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final brightness = Theme.of(context).brightness;
        return AlertDialog(
          title: const Text('Delete user?'),
          content: Text(
            'Delete "@${user['username']}"? This permanently removes their '
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
              child: const Text('Delete'),
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

  @override
  Widget build(BuildContext context) {
    return OneUiPage(
      title: 'Users',
      subtitle: _loading ? null : '${_users.length} account${_users.length == 1 ? '' : 's'}',
      headerAction: IconButton(
        tooltip: 'New user',
        onPressed: _createUser,
        icon: const Icon(Icons.person_add_alt_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _users.isEmpty
              ? OneUiEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No users yet',
                  hint: 'Add the first account to let people in.',
                  actionLabel: 'New user',
                  onAction: _createUser,
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: AppDimens.space24),
                    children: [
                      OneUiGroupedList(
                        header: 'Accounts',
                        withDividers: true,
                        children: [
                          for (final user in _users) _UserTile(
                            user: user,
                            onEdit: () => _editUser(user),
                            onDelete: () => _deleteUser(user),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// "12" GB → "12", null → "" — round-trips the quota field in the editor.
  static String _quotaLabel(num? quotaBytes) {
    if (quotaBytes == null) return '';
    return (quotaBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
  }
}

/// A standard One UI account row: avatar, name, and a one-line meta summary
/// (`@username · role · quota`), with visible Edit and Delete actions on the
/// trailing edge — nothing hidden in an overflow menu.
class _UserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _UserTile({
    required this.user,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final disabled = user['disabled'] == true;
    final isAdmin = user['role'] == 'admin';
    final quotaBytes = (user['quota_bytes'] as num?)?.toInt();
    final accent = AppColors.accentFor(brightness);
    final displayName = user['display_name']?.toString().trim().isNotEmpty == true
        ? user['display_name']!.toString()
        : user['username']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';

    final metaParts = <String>[
      '@$username',
      if (isAdmin) 'ADMIN',
      if (quotaBytes != null)
        '${(quotaBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB'
      else
        'Unlimited',
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
          _UserAction(
            tooltip: 'Edit user',
            icon: Icons.edit_outlined,
            color: AppColors.accentTextFor(brightness),
            onPressed: onEdit,
          ),
          _UserAction(
            tooltip: 'Delete user',
            icon: Icons.delete_outline_rounded,
            color: AppColors.errorFor(brightness),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  String _initial(String name) {
    final letter = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return letter;
  }
}

/// Compact 40dp icon button used in the trailing action row.
class _UserAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _UserAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: AppDimens.iconTile,
        height: AppDimens.iconTile,
      ),
      iconSize: AppDimens.iconMedium,
      icon: Icon(icon, color: color),
    );
  }
}