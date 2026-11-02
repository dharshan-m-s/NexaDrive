import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../../services/session.dart';
import '../../widgets/nexa_components.dart';
import '../login/login_screen.dart';

/// Session management: every session signed in to this account, with a
/// per-session sign-out and the two bulk sign-out actions.
///
/// Contract: the list shows *all* sessions the server returns (the current
/// one first, marked as "This device"), each other session can be revoked
/// individually, and every failure surfaces as a message instead of silently
/// clearing the screen. Signing out this device clears the local session and
/// returns to the sign-in screen.
class SecurityScreen extends StatefulWidget {
  final Session session;
  final Api api;
  const SecurityScreen({super.key, required this.session, required this.api});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  SessionsLoadState loadState = SessionsLoadState.loading;
  List<SessionInfo> sessions = const [];
  Object? error;

  /// True while a sign-out request is in flight; disables every sign-out
  /// affordance so a double tap cannot fire two revokes.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loadState = SessionsLoadState.loading;
      error = null;
    });
    try {
      final list = await widget.api.sessions();
      if (!mounted) return;
      setState(() {
        sessions = list.map(SessionInfo.fromJson).toList()
          ..sort((a, b) {
            // The current session always leads the list; the rest keep the
            // server's most-recent-first order.
            if (a.isCurrent) return -1;
            if (b.isCurrent) return 1;
            return b.lastActivity.compareTo(a.lastActivity);
          });
        loadState = SessionsLoadState.ready;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loadState = SessionsLoadState.failure;
          error = e;
        });
      }
    }
  }

  Future<void> _revoke(SessionInfo target) async {
    final isCurrent = target.isCurrent;
    final name = _deviceLabel(target);
    final confirm = await showNexaConfirmation(
      context: context,
      title: isCurrent ? 'Sign out on this device?' : 'Sign out “$name”?',
      message: isCurrent
          ? 'You will return to the sign-in screen on this device. Other '
              'devices stay signed in.'
          : '“$name” is signed out immediately and must sign in again.',
      confirmText: 'Sign out',
      isDestructive: true,
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    Object? failure;
    try {
      await widget.api.revokeSession(target.id);
    } catch (e) {
      failure = e;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (failure != null) {
      _toast(_errorMessage(failure));
      return;
    }
    if (isCurrent) {
      await _leaveToLogin();
      return;
    }
    await load();
    if (!mounted) return;
    _toast('Signed out $name');
  }

  Future<void> _revokeOtherSessions() async {
    final confirm = await showNexaConfirmation(
      context: context,
      title: 'Sign out of other sessions?',
      message: 'Every other device is signed out immediately. This device '
          'stays signed in.',
      confirmText: 'Sign out of other sessions',
      isDestructive: true,
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    Object? failure;
    try {
      await widget.api.revokeOtherSessions();
    } catch (e) {
      failure = e;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (failure != null) {
      _toast(_errorMessage(failure));
      return;
    }
    await load();
    if (!mounted) return;
    _toast('Other sessions signed out');
  }

  Future<void> _signOutEverywhere() async {
    final confirm = await showNexaConfirmation(
      context: context,
      title: 'Sign out everywhere?',
      message: 'This signs out every device, including this one. You will '
          'return to the sign-in screen.',
      confirmText: 'Sign out everywhere',
      isDestructive: true,
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    Object? failure;
    try {
      await widget.api.signOutEverywhere();
    } catch (e) {
      failure = e;
    }
    if (!mounted) return;

    if (failure != null) {
      setState(() => _busy = false);
      _toast(_errorMessage(failure));
      return;
    }
    await _leaveToLogin();
  }

  /// Clears the local credentials and replaces the stack with the sign-in
  /// screen. Used whenever this device's own session has ended, by revoke or
  /// by signing out everywhere.
  Future<void> _leaveToLogin() async {
    await widget.session.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(session: widget.session),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NexaPage(
      title: 'Security',
      subtitle: 'Sessions and sign-in devices',
      body: switch (loadState) {
        SessionsLoadState.loading => const NexaLoadingBlock(),
        SessionsLoadState.failure => NexaEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Can\u2019t load sessions',
            hint: _errorMessage(error),
            actionLabel: 'Retry',
            actionIcon: Icons.refresh_rounded,
            onAction: load,
            centered: true,
          ),
        SessionsLoadState.ready when sessions.isEmpty => NexaEmptyState(
            icon: Icons.info_outline_rounded,
            title: 'No active sessions',
            hint: 'There are no signed-in sessions for this account right '
                'now. Sign in again to keep working.',
            centered: true,
          ),
        SessionsLoadState.ready => _buildList(),
      },
    );
  }

  Widget _buildList() {
    final brightness = Theme.of(context).brightness;
    SessionInfo? current;
    final others = <SessionInfo>[];
    for (final s in sessions) {
      if (s.isCurrent && current == null) {
        current = s;
      } else {
        others.add(s);
      }
    }

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppDimens.space24),
        children: [
          if (current != null) ...[
            _CurrentDeviceCard(
              session: current,
              busy: _busy,
              onRevoke: () => _revoke(current!),
            ),
            const SizedBox(height: AppDimens.space24),
          ],
          NexaSectionHeader(
            'Other sessions',
            trailing: others.isEmpty
                ? null
                : Text(
                    '${others.length}',
                    style: AppTextStyle.caption1.copyWith(
                      color: AppColors.labelSecondaryFor(brightness),
                    ),
                  ),
          ),
          if (others.isEmpty)
            NexaStatusPod(
              icon: Icons.check_circle_outline_rounded,
              tint: AppColors.successFor(brightness),
              title: 'No other sessions',
              subtitle: 'This account is signed in only on this device.',
            )
          else
            NexaGroupedList(
              withDividers: false,
              children: [
                for (var i = 0; i < others.length; i++) ...[
                  _SessionTile(
                    session: others[i],
                    busy: _busy,
                    onRevoke: () => _revoke(others[i]),
                  ),
                  if (i < others.length - 1) const NexaDivider.inset(),
                ],
              ],
            ),
          const SizedBox(height: AppDimens.space8),
          NexaSectionHeader('Sign out'),
          NexaGroupedList(
            withDividers: false,
            children: [
              NexaListTile(
                leadingIcon: Icons.devices_other_rounded,
                enabled: !_busy,
                showChevron: false,
                title: 'Sign out of other sessions',
                subtitle: 'Keeps this device signed in',
                onTap: _revokeOtherSessions,
              ),
              const NexaDivider.inset(),
              NexaListTile(
                leadingIcon: Icons.logout_rounded,
                leadingIconColor: AppColors.errorFor(brightness),
                enabled: !_busy,
                showChevron: false,
                title: 'Sign out everywhere',
                subtitle: 'Every device, including this one',
                onTap: _signOutEverywhere,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _errorMessage(Object? e) {
    if (e is ApiException) {
      switch (e.status) {
        case 401:
          return 'Your session expired. Sign in again to continue.';
        case 403:
          return 'This session can no longer be managed.';
        default:
          return e.message;
      }
    }
    if (e == null) return 'Something went wrong.';
    return 'Can\u2019t reach the server. Check your connection and try again.';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

enum SessionsLoadState { loading, ready, failure }

class SessionInfo {
  final String id;
  final DateTime createdAt;
  final DateTime lastActivity;
  final DateTime expiresAt;
  final bool isCurrent;
  final String? deviceName;
  final String? platform;

  SessionInfo({
    required this.id,
    required this.createdAt,
    required this.lastActivity,
    required this.expiresAt,
    required this.isCurrent,
    this.deviceName,
    this.platform,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      id: json['session_id']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      lastActivity:
          DateTime.tryParse(json['last_activity_at']?.toString() ?? '') ??
              DateTime.now(),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? '') ??
          DateTime.now(),
      isCurrent: json['is_current'] == true,
      deviceName: json['device_name']?.toString(),
      platform: json['platform']?.toString(),
    );
  }
}

/// The signed-in session, given its own tinted surface so "which one am I on?"
/// is answered at a glance. It carries this device's full timestamps and its
/// own sign-out, styled destructively like every other sign-out row.
class _CurrentDeviceCard extends StatelessWidget {
  final SessionInfo session;
  final bool busy;
  final VoidCallback onRevoke;

  const _CurrentDeviceCard({
    required this.session,
    required this.busy,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final secondary = AppColors.labelSecondaryFor(brightness);
    final subtitle = _currentDeviceSubtitle(session);

    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusCard,
      color: AppColors.accentSubtleFor(brightness),
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppDimens.iconTileLarge,
                height: AppDimens.iconTileLarge,
                decoration: BoxDecoration(
                  color: AppColors.accentContainerFor(brightness),
                  borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
                ),
                child: Icon(
                  _platformIcon(session.platform),
                  size: AppDimens.iconMedium,
                  color: accent,
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
                            'This device',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.title3.copyWith(
                              color: AppColors.labelPrimaryFor(brightness),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppDimens.space8),
                        NexaBadge(label: 'Current', color: accent),
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppDimens.space2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.caption.copyWith(color: secondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space16),
          const NexaDivider(),
          const SizedBox(height: AppDimens.space12),
          _MetaRow(
            label: 'Last active',
            value: _sessionRelativeTime(session.lastActivity),
          ),
          const SizedBox(height: AppDimens.space8),
          _MetaRow(
            label: 'Signed in',
            value: _sessionShortDate(session.createdAt),
          ),
          const SizedBox(height: AppDimens.space8),
          _MetaRow(
            label: 'Expires',
            value: _sessionShortDate(session.expiresAt),
          ),
          const SizedBox(height: AppDimens.space8),
          Tooltip(
            message: 'Sign out of this device',
            child: SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: busy ? null : onRevoke,
                icon: const Icon(
                  Icons.logout_rounded,
                  size: AppDimens.iconSmall,
                ),
                label: const Text('Sign out of this device'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.errorFor(brightness),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppDimens.space12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Any other session: platform, name, freshness, and its own sign-out.
class _SessionTile extends StatelessWidget {
  final SessionInfo session;
  final bool busy;
  final VoidCallback onRevoke;

  const _SessionTile({
    required this.session,
    required this.busy,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final label = _deviceLabel(session);
    final meta = _sessionRelativeTime(session.lastActivity);
    final platform = _platformLabel(session.platform);
    final subtitle = platform == 'Device'
        ? 'Last active $meta'
        : '$platform · Last active $meta';

    return NexaListTile(
      leadingIcon: _platformIcon(session.platform),
      showChevron: false,
      title: label,
      subtitle: subtitle,
      trailing: TextButton.icon(
        onPressed: busy ? null : onRevoke,
        icon: const Icon(Icons.logout_rounded, size: AppDimens.iconSmall),
        label: const Text('Sign out'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.errorFor(brightness),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.space8),
        ),
      ),
    );
  }
}

/// A label/value line inside the current-device card: quiet label on the
/// leading edge, the value right-aligned so the dates form a clean column.
class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyle.footnote.copyWith(
            color: AppColors.labelSecondaryFor(brightness),
          ),
        ),
        const SizedBox(width: AppDimens.space16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyle.footnote.copyWith(
              color: AppColors.labelPrimaryFor(brightness),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Subtitle for the current-device card: the reported device name, else the
/// platform, else nothing — never the "Other session" fallback, which would
/// read as a contradiction under "This device".
String? _currentDeviceSubtitle(SessionInfo session) {
  final name = session.deviceName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final platform = _platformLabel(session.platform);
  return platform == 'Device' ? null : platform;
}

/// Human label for a session row: the device name the client reported, or
/// the platform it came from when the session predates device metadata.
String _deviceLabel(SessionInfo session) {
  final name = session.deviceName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final platform = _platformLabel(session.platform);
  return platform == 'Device' ? 'Other session' : '$platform session';
}

String _platformLabel(String? platform) {
  switch (platform) {
    case 'android':
      return 'Android';
    case 'ios':
      return 'iPhone';
    case 'windows':
      return 'Windows';
    case 'linux':
      return 'Linux';
    case 'macos':
      return 'Mac';
    default:
      return 'Device';
  }
}

IconData _platformIcon(String? platform) {
  switch (platform) {
    case 'android':
      return Icons.phone_android_rounded;
    case 'ios':
      return Icons.phone_iphone_rounded;
    case 'windows':
      return Icons.desktop_windows_rounded;
    case 'macos':
      return Icons.laptop_mac_rounded;
    case 'linux':
      return Icons.computer_rounded;
    default:
      return Icons.devices_other_rounded;
  }
}

String _sessionRelativeTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return _sessionShortDate(time);
}

String _sessionShortDate(DateTime time) {
  return '${time.day}/${time.month}/${time.year}';
}
