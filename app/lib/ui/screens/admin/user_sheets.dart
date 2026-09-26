import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../widgets/one_ui_sheet.dart';
import 'users_controller.dart';

const double _gib = 1024 * 1024 * 1024;

/// Signature of the save callback the editor sheet invokes. Returns an
/// error message to display inside the sheet, or null on success.
typedef UserSaveCallback = Future<String?> Function({
  required String username,
  required String displayName,
  required String password,
  required String role,
  required int? quotaBytes,
  bool clearQuota,
  bool disabled,
});

/// Opens the account editor as a One UI bottom sheet (the single editing
/// surface for both creating and editing an account).
///
/// Validation runs before [onSave]; a returned error string is shown inside
/// the sheet so the user never retypes anything.
Future<bool?> showUserEditorSheet(
  BuildContext context, {
  required String title,
  UserProfile? existing,
  bool usernameLocked = false,
  required UserSaveCallback onSave,
}) {
  return showOneUiSheet<bool>(
    context,
    builder: (_) => _UserEditorSheet(
      title: title,
      existing: existing,
      usernameLocked: usernameLocked,
      onSave: onSave,
    ),
  );
}

class _UserEditorSheet extends StatefulWidget {
  final String title;
  final UserProfile? existing;
  final bool usernameLocked;
  final UserSaveCallback onSave;

  const _UserEditorSheet({
    required this.title,
    required this.onSave,
    this.existing,
    this.usernameLocked = false,
  });

  @override
  State<_UserEditorSheet> createState() => _UserEditorSheetState();
}

class _UserEditorSheetState extends State<_UserEditorSheet> {
  late final TextEditingController _username =
      TextEditingController(text: widget.existing?.username ?? '');
  late final TextEditingController _displayName =
      TextEditingController(text: widget.existing?.displayName ?? '');
  final TextEditingController _password = TextEditingController();
  late final TextEditingController _quota = TextEditingController(
    text: _quotaLabel(widget.existing?.quotaBytes),
  );
  late String _role = (widget.existing?.isAdmin ?? false) ? 'admin' : 'user';
  late bool _disabled = widget.existing?.disabled ?? false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    _quota.dispose();
    super.dispose();
  }

  String? _validate() {
    if (!_isEdit && _username.text.trim().isEmpty) {
      return 'Enter a username.';
    }
    if (_displayName.text.trim().isEmpty) return 'Enter a display name.';
    if (_password.text.isNotEmpty && _password.text.length < 10) {
      return 'Password must be at least 10 characters';
    }
    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final raw = _quota.text.trim();
    int? quotaBytes;
    var clearQuota = false;
    if (raw.isEmpty) {
      clearQuota = _isEdit;
    } else {
      final gb = double.tryParse(raw);
      if (gb == null || gb < 0) {
        setState(() {
          _saving = false;
          _error = 'Quota must be a number of GB, or leave it empty';
        });
        return;
      }
      quotaBytes = (gb * _gib).round();
    }

    try {
      final error = await widget.onSave(
        username: _username.text.trim(),
        displayName: _displayName.text.trim(),
        password: _password.text,
        role: _role,
        quotaBytes: quotaBytes,
        clearQuota: clearQuota,
        disabled: _disabled,
      );
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _saving = false;
          _error = error;
        });
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return OneUiSheetBody(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OneUiSheetHeader(title: widget.title),
          const SizedBox(height: AppDimens.space8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _username,
                    enabled: !_isEdit,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      helperText:
                          _isEdit ? 'Usernames cannot be changed' : null,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space12),
                  TextField(
                    controller: _displayName,
                    decoration:
                        const InputDecoration(labelText: 'Display name'),
                  ),
                  const SizedBox(height: AppDimens.space12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText:
                          _isEdit ? 'New password (optional)' : 'Password',
                      helperText: _isEdit
                          ? 'Leave empty to keep the current password. '
                              'Changing it signs this user out everywhere.'
                          : 'At least 10 characters',
                    ),
                  ),
                  const SizedBox(height: AppDimens.space12),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('User')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    ],
                    onChanged: (v) => setState(() => _role = v ?? 'user'),
                    decoration: const InputDecoration(labelText: 'Role'),
                  ),
                  const SizedBox(height: AppDimens.space12),
                  TextField(
                    controller: _quota,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Quota (GB, optional)',
                      helperText: _isEdit ? 'Empty = unlimited' : null,
                    ),
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: AppDimens.space8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Block account',
                        style: AppTextStyle.rowTitle.copyWith(
                          color: AppColors.textPrimaryFor(brightness),
                        ),
                      ),
                      subtitle: Text(
                        'Prevents this user from logging in without deleting '
                        'their files.',
                        style: AppTextStyle.caption.copyWith(
                          color: AppColors.textSecondaryFor(brightness),
                        ),
                      ),
                      value: _disabled,
                      onChanged: (v) => setState(() => _disabled = v),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppDimens.space4),
                    Text(
                      _error!,
                      style: AppTextStyle.caption.copyWith(
                        color: AppColors.errorFor(brightness),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppDimens.space16),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppDimens.space12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: Text(_saving
                      ? 'Saving…'
                      : (_isEdit ? 'Save changes' : 'Create')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _quotaLabel(int? quotaBytes) {
    if (quotaBytes == null) return '';
    final gb = quotaBytes / _gib;
    return gb == gb.roundToDouble()
        ? gb.toStringAsFixed(0)
        : gb.toStringAsFixed(1);
  }
}

/// Opens the per-account actions sheet: edit, block/unblock, delete, with the
/// protection reason shown inline when the row is guarded.
Future<void> showUserActionsSheet(
  BuildContext context, {
  required UserProfile user,
  required String? protectedReason,
  required VoidCallback onEdit,
  required Future<void> Function() onToggleBlock,
  required VoidCallback onDelete,
}) {
  return showOneUiSheet<void>(
    context,
    builder: (_) => _UserActionsSheet(
      user: user,
      protectedReason: protectedReason,
      onEdit: onEdit,
      onToggleBlock: onToggleBlock,
      onDelete: onDelete,
    ),
  );
}

class _UserActionsSheet extends StatelessWidget {
  final UserProfile user;
  final String? protectedReason;
  final VoidCallback onEdit;
  final Future<void> Function() onToggleBlock;
  final VoidCallback onDelete;

  const _UserActionsSheet({
    required this.user,
    required this.protectedReason,
    required this.onEdit,
    required this.onToggleBlock,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return OneUiSheetBody(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OneUiSheetHeader(
            title: user.displayName,
            subtitle: '@${user.username}',
          ),
          if (protectedReason != null) ...[
            Padding(
              padding: const EdgeInsets.only(
                bottom: AppDimens.space8,
                left: AppDimens.space4,
                right: AppDimens.space4,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: AppDimens.iconSmall,
                    color: AppColors.warningFor(brightness),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Expanded(
                    child: Text(
                      protectedReason!,
                      style: AppTextStyle.caption.copyWith(
                        color: AppColors.textSecondaryFor(brightness),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          OneUiSheetAction(
            icon: Icons.edit_outlined,
            title: 'Edit account',
            onTap: () {
              Navigator.pop(context);
              onEdit();
            },
          ),
          OneUiSheetAction(
            icon: user.disabled ? Icons.lock_open_rounded : Icons.block_rounded,
            title: user.disabled ? 'Unblock account' : 'Block account',
            onTap: () {
              Navigator.pop(context);
              onToggleBlock();
            },
          ),
          OneUiSheetAction(
            icon: Icons.delete_outline_rounded,
            title: 'Delete account',
            destructive: true,
            enabled: protectedReason == null,
            onTap: protectedReason == null
                ? () {
                    Navigator.pop(context);
                    onDelete();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
