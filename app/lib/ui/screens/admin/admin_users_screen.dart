import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_surface.dart';

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _toggleDisabled(Map<String, dynamic> user) async {
    try {
      await widget.api.updateUser(
        user['id'] as String,
        disabled: user['disabled'] == true ? false : true,
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
                    decoration: const InputDecoration(labelText: 'Password')),
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
    if (password.text.trim().length < 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password must be at least 8 characters')),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          IconButton(
            tooltip: 'New user',
            onPressed: _createUser,
            icon: const Icon(Icons.person_add_alt_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _users.isEmpty
              ? const OneUiEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No users yet',
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.pageMargin, AppDimens.space8, AppDimens.pageMargin, AppDimens.space24,
                    ),
                    itemCount: _users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppDimens.space2),
                    itemBuilder: (context, i) {
                      final user = _users[i];
                      final disabled = user['disabled'] == true;
                      final isAdmin = user['role'] == 'admin';
                      final usedBytes = (user['used_bytes'] as num?)?.toInt() ?? 0;
                      final quotaBytes = (user['quota_bytes'] as num?)?.toInt();
                      final brightness = Theme.of(context).brightness;
                      return OneUiSurface(
                        level: OneUiSurfaceLevel.surface,
                        radius: AppDimens.radiusTile,
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppDimens.radiusTile),
                          ),
                          enabled: !disabled,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.accentFor(brightness)
                                .withValues(alpha: 0.14),
                            child: Text(
                              _initial(user),
                              style: AppTextStyle.buttonSmall.copyWith(
                                color: AppColors.accentFor(brightness),
                              ),
                            ),
                          ),
                          title: Text(
                            user['display_name']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '@${user['username'] ?? ''}'
                            ' · ${isAdmin ? 'Admin' : 'User'}'
                            '${quotaBytes != null ? ' · ${(usedBytes / 1024 / 1024 / 1024).toStringAsFixed(2)} / ${(quotaBytes / 1024 / 1024 / 1024).toStringAsFixed(0)} GB' : ''}'
                            '${disabled ? ' · Disabled' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            tooltip: disabled ? 'Enable user' : 'Disable user',
                            icon: Icon(
                              disabled ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                              color: disabled
                                  ? AppColors.successFor(brightness)
                                  : AppColors.errorFor(brightness),
                            ),
                            onPressed: () => _toggleDisabled(user),
                          ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  String _initial(Map<String, dynamic> user) {
    final name = user['display_name']?.toString() ?? '';
    final letter = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return letter;
  }
}