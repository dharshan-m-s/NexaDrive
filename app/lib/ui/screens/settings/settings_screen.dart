import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../../services/app_lock.dart';
import '../../../services/session.dart';
import '../../../update/update_controller.dart';
import '../../widgets/one_ui_grouped_list.dart';
import '../../widgets/one_ui_page.dart';
import '../admin/audit_log_screen.dart';
import '../admin/users_screen.dart';
import 'update_center_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Session session;
  final Api api;
  final UpdateController updateController;
  final VoidCallback onLogout;
  final VoidCallback onOpenSync;
  final VoidCallback onOpenTransfers;
  final VoidCallback onOpenNotifications;

  const SettingsScreen({
    super.key,
    required this.session,
    required this.api,
    required this.updateController,
    required this.onLogout,
    required this.onOpenSync,
    required this.onOpenTransfers,
    required this.onOpenNotifications,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AppLockService _appLock = AppLockService();
  bool? _appLockEnabled;

  @override
  void initState() {
    super.initState();
    // Only Android implements App Lock (device credential); the setting is
    // meaningless elsewhere and would only promise something it cannot do.
    if (Platform.isAndroid) {
      _appLock.isEnabled().then((value) {
        if (mounted) setState(() => _appLockEnabled = value);
      });
    }
  }

  String get _initial {
    final name = widget.session.displayName?.trim().isNotEmpty == true
        ? widget.session.displayName!
        : (widget.session.username ?? 'N');
    return name.characters.first.toUpperCase();
  }

  Future<void> _changeTheme(BuildContext context) async {
    final current = widget.session.themeMode;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Appearance'),
        children: ['system', 'light', 'dark'].map((mode) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, mode),
            child: Row(
              children: [
                Icon(
                  mode == 'system'
                      ? Icons.brightness_auto_rounded
                      : mode == 'light'
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                  size: AppDimens.iconMedium,
                ),
                const SizedBox(width: AppDimens.space12),
                Text(mode[0].toUpperCase() + mode.substring(1)),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (value == null || value == current) return;
    await widget.session.setThemeMode(value);
  }

  /// Toggles App Lock. Turning it on asks the device once whether it actually
  /// has a secure lock; a device without one refuses, and the user is told why
  /// instead of being given a switch that silently does nothing.
  Future<void> _toggleAppLock(bool value) async {
    final ok = await _appLock.setEnabled(value);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'This device has no screen lock. Set a PIN, pattern or '
              'biometric in Android settings first.',
            ),
          ),
        );
      return;
    }
    setState(() => _appLockEnabled = value);
    if (value) {
      // Immediate proof the lock works, instead of a surprise at next launch.
      final result = await _appLock.authenticate();
      if (!mounted) return;
      if (result != AppLockResult.unlocked) {
        await _appLock.setEnabled(false);
        if (mounted) setState(() => _appLockEnabled = false);
      }
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('signout_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirm == true) widget.onLogout();
  }

  Future<void> _showServerDialog(BuildContext context) async {
    final serverUrl = widget.session.serverUrl ?? '';
    final snack = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connected to'),
        content: Text(
          serverUrl.isEmpty ? 'Not configured' : serverUrl,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: serverUrl));
              Navigator.pop(context);
              snack.showSnackBar(
                const SnackBar(content: Text('Server address copied')),
              );
            },
            child: const Text('Copy address'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isAdmin = widget.session.role == 'admin';
    final accent = AppColors.accentFor(brightness);
    final secondary = AppColors.textSecondaryFor(brightness);
    final session = widget.session;

    return OneUiPage(
      title: 'Settings',
      subtitle: session.username ?? '',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Profile header
          Center(
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: brightness == Brightness.dark
                        ? accent.withValues(alpha: 0.18)
                        : accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _initial,
                    style: AppTextStyle.display.copyWith(
                      color: accent,
                      fontSize: 30,
                    ),
                  ),
                ),
                const SizedBox(height: AppDimens.space12),
                Text(
                  session.displayName ?? session.username ?? '',
                  style: AppTextStyle.sectionHeader.copyWith(
                    color: AppColors.textPrimaryFor(brightness),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                Text(
                  isAdmin ? 'Administrator' : (session.username ?? ''),
                  style: AppTextStyle.caption.copyWith(color: secondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.space32),

          OneUiGroupedList(
            header: 'General',
            children: [
              OneUiGroupTile(
                icon: Icons.brightness_6_rounded,
                title: 'Appearance',
                subtitle: _themeLabel(session.themeMode),
                onTap: () => _changeTheme(context),
              ),
              if (Platform.isAndroid && _appLockEnabled != null)
                OneUiGroupTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'App Lock',
                  subtitle: _appLockEnabled == true
                      ? 'Locked with your device screen lock'
                      : 'Off',
                  showChevron: false,
                  trailing: Switch(
                    value: _appLockEnabled == true,
                    onChanged: _toggleAppLock,
                  ),
                ),
              OneUiGroupTile(
                icon: Icons.sync_rounded,
                title: 'Sync center',
                subtitle: 'Keep a local folder in step with the cloud',
                onTap: widget.onOpenSync,
              ),
              OneUiGroupTile(
                icon: Icons.cloud_upload_outlined,
                title: 'Transfers',
                subtitle: 'Offline upload queue and progress',
                onTap: widget.onOpenTransfers,
              ),
              OneUiGroupTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: 'Backup and account alerts',
                onTap: widget.onOpenNotifications,
              ),
            ],
          ),

          OneUiGroupedList(
            header: 'Server',
            children: [
              OneUiGroupTile(
                icon: Icons.dns_outlined,
                title: 'Connected to',
                subtitle: session.serverUrl ?? 'Not configured',
                onTap: () => _showServerDialog(context),
              ),
            ],
          ),

          if (isAdmin) ...[
            OneUiGroupedList(
              header: 'Admin',
              children: [
                OneUiGroupTile(
                  icon: Icons.people_outline_rounded,
                  title: 'Users',
                  subtitle: 'Manage accounts and quotas',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UsersScreen(api: widget.api),
                      ),
                    );
                  },
                ),
                OneUiGroupTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Audit log',
                  subtitle: 'Review what happened and when',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuditLogScreen(api: widget.api),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],

          OneUiGroupedList(
            header: 'About',
            children: [
              _UpdateCenterTile(controller: widget.updateController),
              OneUiGroupTile(
                icon: Icons.info_outline_rounded,
                title: 'About NexaDrive',
                subtitle: 'Your files. Your server. Your private cloud.',
                onTap: () {
                  // Only state a version when the controller actually knows it.
                  // A hardcoded fallback here was a release literal that went
                  // stale at the next release; `showAboutDialog` omits the
                  // version line entirely when it is null.
                  showAboutDialog(
                    context: context,
                    applicationName: 'NexaDrive',
                    applicationVersion:
                        widget.updateController.currentVersion?.toString(),
                    applicationLegalese:
                        'Your files. Your server. Your private cloud.',
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: AppDimens.space24),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => _confirmLogout(context),
              icon: const Icon(Icons.logout_rounded, size: AppDimens.iconSmall),
              label: const Text('Sign out'),
            ),
          ),
          const SizedBox(height: AppDimens.space8),
        ],
      ),
    );
  }

  String _themeLabel(String mode) {
    switch (mode) {
      case 'light':
        return 'Light';
      case 'dark':
        return 'Dark';
      default:
        return 'System default';
    }
  }
}

/// Settings entry to the Update Center with a subtle availability indicator.
class _UpdateCenterTile extends StatelessWidget {
  final UpdateController controller;
  const _UpdateCenterTile({required this.controller});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final (subtitle, badge) = _statusFor(brightness);
        return OneUiGroupTile(
          icon: Icons.system_update_alt_rounded,
          title: 'Update center',
          subtitle: subtitle,
          trailing: badge,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UpdateCenterScreen(controller: controller),
              ),
            );
          },
        );
      },
    );
  }

  (String, Widget?) _statusFor(Brightness brightness) {
    final accent = AppColors.accentFor(brightness);
    final onWarning = AppColors.onWarningContainerFor(brightness);
    final warningBg = AppColors.warningContainerFor(brightness);

    switch (controller.status) {
      case UpdateStatus.updateAvailable:
        return (
          controller.manifestVersionLabel != null
              ? 'Update to ${controller.manifestVersionLabel}'
              : 'A new version is available',
          _badge(onWarning, warningBg, 'Update'),
        );
      case UpdateStatus.mandatory:
        return (
          'Required for continued use',
          _badge(onWarning, warningBg, 'Required'),
        );
      case UpdateStatus.paused:
        return ('Download paused', null);
      case UpdateStatus.downloading:
        final pct = (controller.progress * 100).round();
        return ('Downloading… $pct%', _dot(accent));
      case UpdateStatus.checking:
        return ('Checking for updates…', _dot(accent));
      case UpdateStatus.readyToInstall:
        return ('Installer ready', null);
      case UpdateStatus.installingHandoff:
        return ('Finish the installation', null);
      case UpdateStatus.completed:
        return ('New version installed', null);
      case UpdateStatus.failed:
      case UpdateStatus.offline:
      case UpdateStatus.unsupported:
      case UpdateStatus.cancelled:
        return ('Check for app updates', null);
      case UpdateStatus.upToDate:
        return (
          controller.manifestVersionLabel != null
              ? 'Up to date · ${controller.manifestVersionLabel}'
              : 'Up to date',
          null,
        );
      case UpdateStatus.verifying:
        return ('Verifying download…', _dot(accent));
      case UpdateStatus.idle:
        return ('Check for app updates', null);
      case UpdateStatus.needsUserAction:
        return ('Grant install permission', null);
    }
  }

  Widget _badge(Color fg, Color bg, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space10,
        vertical: AppDimens.space4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Text(
        label,
        style: AppTextStyle.chipLabel.copyWith(color: fg),
      ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
