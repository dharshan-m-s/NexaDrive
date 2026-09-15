import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../services/api.dart';
import '../../../services/session.dart';
import '../../../services/transfer_queue.dart';
import '../../../services/sync_service.dart';
import '../../../services/background_transfer_service.dart';
import '../screens/home/home_screen.dart';
import '../screens/files/files_screen.dart';
import '../screens/shared/shared_screen.dart';
import '../screens/photos/photos_screen.dart';
import '../screens/trash/trash_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/sync/sync_center_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/transfers/transfers_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/scanner/scanner_screen.dart';
import '../../update/android_updater_channel.dart';
import '../../update/app_platform.dart';
import '../../update/update_controller.dart';
import '../../update/update_downloader.dart';
import '../../update/update_source.dart';
import '../widgets/one_ui_sheet.dart';
import 'navigation.dart';

/// Application shell: brand, navigation context, and the active screen.
///
/// Mobile uses a One UI bottom navigation; desktop uses a persistent sidebar
/// rail. On wide screens a transfer status strip surfaces the offline queue.
class AppShell extends StatefulWidget {
  final Session session;
  final SharedPreferences prefs;
  const AppShell({super.key, required this.session, required this.prefs});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int index = 0;
  late final Api api;
  late final UpdateController updateController;
  Timer? _queueTimer;
  bool _handlingExpiredSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _queueTimer = Timer.periodic(const Duration(seconds: 30), (_) => _resumeQueue());
    api = Api(widget.session);
    api.onUnauthorized = _handleSessionExpired;
    updateController = UpdateController(
      source: UpdateSource(),
      downloader: UpdateDownloader(),
      detector: AppPlatformDetector(
        abiResolver: UpdaterMethodChannel().resolveAbi,
      ),
      selector: const ArtifactSelector(),
      preferences: UpdatePreferences(widget.prefs),
      router: const UpdateRouter(),
    );
    _pruneUpdateCache();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkServerAndQueue();
      _autoSync();
      // Once-per-day silent update check (policy throttles to 24h).
      updateController.checkForUpdates();
    });
  }

  void _pruneUpdateCache() {
    // Bounded download cache: prune keeps files only within size/age limits
    // and clears stale partials, all best-effort.
    UpdateCache.prune().catchError((_) {});
  }

  bool _syncRunning = false;

  Future<void> _autoSync() async {
    if (_syncRunning || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return;
    }
    final manager = SyncManager(api);
    if (await manager.folder() == null) return;
    _syncRunning = true;
    try {
      final result = await manager.sync();
      if (!mounted) return;
      if (result.conflicts > 0 || result.errors > 0) {
        _toast('Sync needs attention: ${result.conflicts} conflict(s), ${result.errors} error(s).');
      }
    } finally {
      _syncRunning = false;
    }
  }

  Future<void> _resumeQueue() async {
    try {
      final queue = TransferQueue(api);
      final pending = (await queue.items()).where((x) => x.status != 'completed').toList();
      if (pending.isNotEmpty) await queue.process(onChanged: (_) {});
    } catch (_) {}
  }

  Future<void> _checkServerAndQueue() async {
    try {
      final status = await api.serverStatus();
      updateController.noteServerVersion(
        status['version'] as String?,
        status['api_version'] as String?,
      );
      final prefs = await SharedPreferences.getInstance();
      final current = status['instance_id'] as String?;
      final previous = prefs.getString('nexadrive_server_instance');
      await prefs.setString('nexadrive_server_instance', current ?? '');
      if (mounted && previous != null && current != null && previous.isNotEmpty && previous != current) {
        _toast('The server restarted. Interrupted transfers are safe in the queue.');
      }
      final queue = TransferQueue(api);
      final pending = (await queue.items()).where((x) => x.status != 'completed').toList();
      if (pending.isNotEmpty) {
        await queue.process(onChanged: (_) {});
        if (mounted) setState(() {});
      }
    } catch (_) {
      // Offline/server-down is surfaced by the queue and page requests.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeQueue();
      _autoSync();
      // If the user was mid-Android/Windows install, confirm success or
      // resume the Update Center with a clear "finish or retry" state.
      updateController.reconcileAfterResume();
    }
  }

  Future<void> _handleSessionExpired() async {
    if (_handlingExpiredSession) return;
    _handlingExpiredSession = true;
    try {
      await BackgroundTransferService.cancel();
    } catch (_) {}
    try {
      await widget.session.clear();
    } catch (_) {}
    if (!mounted || !context.mounted) return;
    _toast('Session expired. Please sign in again.');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(session: widget.session)),
      (_) => false,
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSyncCenter() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SyncCenterScreen(api: api)),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NotificationsScreen(api: api)),
    );
  }

  void _openTransfers() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TransfersScreen(api: api)),
    );
  }

  Future<void> _showMoreSheet() async {
    await showOneUiSheet<void>(
      context,
      builder: (sheetContext) => OneUiSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OneUiSheetHeader(title: 'More'),
            OneUiSheetAction(
              icon: Icons.camera_alt_rounded,
              title: 'Scan document',
              subtitle: 'Snap a page and save it to My files',
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ScannerScreen(api: api),
                  ),
                );
              },
            ),
            OneUiSheetAction(
              icon: Icons.cloud_upload_outlined,
              title: 'Transfers',
              subtitle: 'Uploads waiting for a connection',
              onTap: () {
                Navigator.pop(sheetContext);
                _openTransfers();
              },
            ),
            OneUiSheetAction(
              icon: Icons.delete_outline_rounded,
              title: 'Trash',
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => index = 4);
              },
            ),
            OneUiSheetAction(
              icon: Icons.sync_rounded,
              title: 'Sync center',
              onTap: () {
                Navigator.pop(sheetContext);
                _openSyncCenter();
              },
            ),
            OneUiSheetAction(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              onTap: () {
                Navigator.pop(sheetContext);
                _openNotifications();
              },
            ),
            OneUiSheetAction(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => index = 5);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> logout() async {
    await BackgroundTransferService.cancel();
    await api.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(session: widget.session)),
      (_) => false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _queueTimer?.cancel();
    updateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 900;

    final pages = <Widget>[
      HomeScreen(session: widget.session, api: api, onNavigate: (value) => setState(() => index = value)),
      FilesScreen(api: api),
      SharedScreen(api: api),
      PhotosScreen(api: api, session: widget.session),
      TrashScreen(api: api),
      SettingsScreen(
        session: widget.session,
        api: api,
        updateController: updateController,
        onLogout: logout,
        onOpenSync: _openSyncCenter,
        onOpenTransfers: _openTransfers,
        onOpenNotifications: _openNotifications,
      ),
    ];

    return Scaffold(
      body: desktop
          ? Row(
              children: [
                SideNavigation(
                  index: index,
                  onSelected: (value) => setState(() => index = value),
                  onSync: _openSyncCenter,
                  onTransfers: _openTransfers,
                  onNotifications: _openNotifications,
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: AppDimens.contentMaxWidth),
                      child: _PageHost(key: ValueKey('page_$index'), child: pages[index]),
                    ),
                  ),
                ),
              ],
            )
          : Stack(
              children: [
                Positioned.fill(child: _PageHost(key: ValueKey('page_$index'), child: pages[index])),
              ],
            ),
      bottomNavigationBar: desktop
          ? null
          : OneUiBottomNav(
              index: index >= 4 ? 4 : index,
              onSelected: (value) {
                if (value == 4) {
                  _showMoreSheet();
                } else {
                  setState(() => index = value);
                }
              },
            ),
    );
  }
}

class _PageHost extends StatelessWidget {
  final Widget child;
  const _PageHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, AppMotion.fast),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      child: SafeArea(child: child),
    );
  }
}