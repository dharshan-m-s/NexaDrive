import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../core/design/app_motion.dart';
import '../../../services/api.dart';
import '../../../services/session.dart';
import '../../../services/upload_item.dart';
import '../../../services/upload_manager.dart';
import '../../../services/sync_service.dart';
import '../../../services/media_cache.dart';
import '../../../services/thumbnail_cache.dart';
import '../../../services/background_transfer_service.dart';
import '../../../services/android_share_intents.dart';
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
import '../screens/search/search_screen.dart';
import '../widgets/folder_picker.dart';
import '../../update/android_updater_channel.dart';
import '../../update/app_platform.dart';
import '../../update/update_controller.dart';
import '../../update/update_downloader.dart';
import '../../update/update_source.dart';
import '../widgets/nexa_components.dart';
import 'navigation.dart';

/// Application shell: brand, navigation context, and the active screen.
///
/// Mobile uses the signature floating Material 3 pill; desktop uses a
/// navigation rail. On wide screens a transfer status strip surfaces the queue.
class AppShell extends StatefulWidget {
  final Session session;
  final SharedPreferences prefs;

  /// Overrides the API client. Only used by tests, which need a deterministic
  /// server without touching the network.
  final Api? api;

  const AppShell({
    super.key,
    required this.session,
    required this.prefs,
    this.api,
  });

  /// Shared Navigator observer so any route pushed above the shell dismisses
  /// the More overlay, even when the push came from a page outside the shell.
  static final RouteObserver<ModalRoute<dynamic>> routeObserver =
      RouteObserver<ModalRoute<dynamic>>();

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin, RouteAware {
  int index = 0;
  late final Api api;
  late final UpdateController updateController;
  Timer? _queueTimer;
  late final UploadManager _uploads;
  StreamSubscription<UploadEvent>? _transferEvents;
  bool _transferStripVisible = false;
  Timer? _transferStripHoldTimer;
  int _failedTransferCount = 0;
  Timer? _transferNoticeTimer;
  bool _handlingExpiredSession = false;
  bool _moreSheetOpen = false;
  ModalRoute<dynamic>? _observedRoute;
  _PillNotice? _pillNotice;
  int _pillNoticeId = 0;
  bool _shareSheetShowing = false;
  bool _deferShareProcessing = false;
  final Set<String> _activeSharedUris = <String>{};
  final List<AndroidSharedFile> _queuedSharedFiles = [];

  /// Destinations the user has actually opened.
  ///
  /// The shell keeps visited pages alive so switching tabs preserves scroll
  /// position, the open folder, and the loaded listing instead of re-fetching
  /// everything. Pages are built on first visit so launch does not fire six
  /// simultaneous requests.
  final Set<int> _visited = <int>{0};

  /// Number of destinations in the shell.
  static const int _pageCount = 6;

  void _goTo(int value) {
    if (value < 0 || value >= _pageCount) return;
    _closeMoreMenu();
    setState(() {
      index = value;
      _visited.add(value);
    });
  }

  void _handleSystemBack(bool didPop) {
    if (didPop) return;
    // The More panel is the topmost layer: dismiss it before changing tabs so
    // back never leaves an orphaned scrim over a different destination.
    if (_moreSheetOpen) {
      _closeMoreMenu();
      return;
    }
    if (index != 0 && index != 1) _goTo(0);
  }

  /// Opens My files and asks it to start [intent], so a Home shortcut performs
  /// the action it names rather than just navigating.
  void _openFiles(FilesIntent intent) {
    _closeMoreMenu();
    setState(() {
      _filesIntent = intent;
      index = 1;
      _visited.add(1);
    });
  }

  /// Cleared as soon as My files has started the action.
  FilesIntent? _filesIntent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(AndroidShareIntents.initialize(_queueSharedFiles));
    _queueTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _resumeQueue());
    api = widget.api ?? Api(widget.session);
    api.onUnauthorized = _handleSessionExpired;
    // The upload queue uploads through this client and picks up transfers
    // that were interrupted by an earlier crash. The shell claims the queue
    // for the foreground app, so the Android background worker knows to stay
    // out of the way while the app is open.
    _uploads = UploadManager.current;
    _uploads
      ..attach(api)
      ..claimForeground();
    _transferStripVisible = _hasTransferActivity();
    _uploads.addListener(_refreshTransferStrip);
    _transferEvents = _uploads.events.listen(_handleUploadEvent);
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
    MediaCache.purgeLegacy().catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkServerAndQueue();
      _autoSync();
      // Once-per-day silent update check (policy throttles to 24h).
      updateController.checkForUpdates();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _observedRoute)) return;
    if (_observedRoute != null) {
      AppShell.routeObserver.unsubscribe(this);
    }
    _observedRoute = route;
    if (route != null) AppShell.routeObserver.subscribe(this, route);
  }

  @override
  void didPushNext() => _closeMoreMenu();

  @override
  void didPopNext() => _closeMoreMenu();

  @override
  void didPop() => _closeMoreMenu();

  void _pruneUpdateCache() {
    // Bounded download cache: prune keeps files only within size/age limits
    // and clears stale partials, all best-effort.
    UpdateCache.prune().catchError((_) {});
  }

  bool _syncRunning = false;

  Future<void> _autoSync() async {
    if (_syncRunning ||
        (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return;
    }
    final manager = SyncManager(api);
    if (await manager.folder() == null) return;
    _syncRunning = true;
    try {
      final result = await manager.sync();
      if (!mounted) return;
      if (result.conflicts > 0 || result.errors > 0) {
        _toast(
          'Sync needs attention: ${result.conflicts} conflict(s), ${result.errors} error(s).',
        );
      }
    } finally {
      _syncRunning = false;
    }
  }

  /// Nudges the upload queue to pick up whatever is still pending.
  Future<void> _resumeQueue() async {
    try {
      final manager = UploadManager.current;
      manager.attach(api);
      // A transfer that was running when the app went away is marked as
      // queued again; the worker asks the server for the authoritative offset
      // before it sends a byte.
      await manager.requeueInterrupted();
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
      if (mounted &&
          previous != null &&
          current != null &&
          previous.isNotEmpty &&
          previous != current) {
        _toast(
          'The server restarted. Interrupted transfers are safe in the queue.',
        );
      }
      final manager = UploadManager.current;
      manager.attach(api);
      if (manager.pendingCount > 0) {
        await manager.requeueInterrupted();
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
    await _purgeLocalCaches();
    if (!mounted || !context.mounted) return;
    _toast('Session expired. Please sign in again.');
    unawaited(_resetToRoute(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(session: widget.session),
      ),
    ));
  }

  /// General ambient feedback lives in the pill's own bounds. No route, scrim
  /// or global SnackBar queue is involved, so nothing can outlive the notice.
  void _toast(String message) => _showPillNotice(message);

  void _showPillNotice(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    setState(() {
      _pillNotice = _PillNotice(
        id: ++_pillNoticeId,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      );
    });
  }

  void _dismissPillNotice(int id) {
    if (!mounted || _pillNotice?.id != id) return;
    setState(() => _pillNotice = null);
  }

  bool _hasTransferActivity() => _uploads.items().any(
        (item) =>
            item.state == UploadState.queued ||
            item.state == UploadState.uploading ||
            item.state == UploadState.retrying ||
            item.state == UploadState.paused ||
            item.state == UploadState.failed,
      );

  /// Reserve room for the live strip, including any growth from large text.
  double _transferStripSpace(double gap) =>
      MediaQuery.textScalerOf(context).scale(AppDimens.transferStripHeight) +
      gap;

  void _holdTransferStrip() {
    if (!mounted) return;
    if (!_transferStripVisible) {
      setState(() => _transferStripVisible = true);
    }
    _transferStripHoldTimer?.cancel();
    _transferStripHoldTimer = Timer(AppMotion.ambient * 2, () {
      _transferStripHoldTimer = null;
      if (!mounted || _hasTransferActivity()) return;
      setState(() => _transferStripVisible = false);
    });
  }

  void _refreshTransferStrip() {
    if (!mounted) return;
    if (_hasTransferActivity()) {
      _transferStripHoldTimer?.cancel();
      _transferStripHoldTimer = null;
      if (!_transferStripVisible) {
        setState(() => _transferStripVisible = true);
      }
      return;
    }
    // Keep the last transfer's summary readable for a moment after completion;
    // the strip is the completion feedback, so a popup is never needed.
    if (!_transferStripVisible || _transferStripHoldTimer != null) return;
    _holdTransferStrip();
  }

  void _handleUploadEvent(UploadEvent event) {
    if (!mounted) return;
    if (event.kind == UploadEventKind.completed) {
      // A short upload can finish before the coalesced queue tick runs. Show
      // the completion surface from the event itself so it is never skipped.
      _holdTransferStrip();
      return;
    }
    if (event.kind != UploadEventKind.failed) return;
    _failedTransferCount++;
    _transferNoticeTimer?.cancel();
    _transferNoticeTimer = Timer(AppMotion.normal, _flushTransferNotices);
  }

  void _flushTransferNotices() {
    if (!mounted) return;
    final failed = _failedTransferCount;
    _failedTransferCount = 0;
    if (failed == 0) return;
    _showPillNotice(
      failed == 1
          ? 'That upload didn’t finish'
          : '$failed uploads didn’t finish',
      actionLabel: 'Retry',
      onAction: () => unawaited(_uploads.retryFailed()),
    );
  }

  Future<void> _cancelAllTransfers() async {
    final removable = _uploads
        .items()
        .where(
          (item) =>
              item.state != UploadState.completed &&
              item.state != UploadState.cancelled,
        )
        .map((item) => item.id)
        .toList(growable: false);
    for (final id in removable) {
      await _uploads.remove(id);
    }
  }

  Widget _buildTransferStrip({double maxWidth = AppDimens.bottomNavMaxWidth}) {
    if (!_transferStripVisible || _shareSheetShowing || _moreSheetOpen) {
      return const SizedBox.shrink();
    }
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space12,
          ),
          child: ActiveTransferStrip(
            manager: _uploads,
            onOpen: _openTransfers,
            onPauseAll: () => unawaited(_uploads.pauseAll()),
            onResumeAll: () => unawaited(_uploads.resumeAll()),
            onRetryFailed: () => unawaited(_uploads.retryFailed()),
            onCancelAll: () => unawaited(_cancelAllTransfers()),
          ),
        ),
      ),
    );
  }

  /// Every shell-initiated route goes through here so no page or sheet can be
  /// pushed while the More scrim is still mounted.
  Future<void> _pushRoute(Route<void> route) async {
    _closeMoreMenu();
    if (!mounted) return;
    await Navigator.of(context).push<void>(route);
  }

  Future<void> _resetToRoute(Route<void> route) async {
    _closeMoreMenu();
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil<void>(route, (_) => false);
  }

  void _openSyncCenter() {
    unawaited(_pushRoute(
      MaterialPageRoute<void>(builder: (_) => SyncCenterScreen(api: api)),
    ));
  }

  void _openNotifications() {
    unawaited(_pushRoute(
      MaterialPageRoute<void>(builder: (_) => NotificationsScreen(api: api)),
    ));
  }

  void _openTransfers() {
    unawaited(_pushRoute(
      MaterialPageRoute<void>(builder: (_) => const TransfersScreen()),
    ));
  }

  Future<void> _showCommandPalette() async {
    _closeMoreMenu();
    if (!mounted) return;
    final controller = TextEditingController();
    final commands = <(IconData icon, String label, VoidCallback action)>[
      (Icons.home_outlined, 'Go to Home', () => _goTo(0)),
      (Icons.folder_outlined, 'Go to My files', () => _goTo(1)),
      (Icons.people_outline_rounded, 'Go to Shared', () => _goTo(2)),
      (Icons.photo_library_outlined, 'Go to Photos', () => _goTo(3)),
      (Icons.delete_outline_rounded, 'Go to Trash', () => _goTo(4)),
      (Icons.settings_outlined, 'Go to Settings', () => _goTo(5)),
      (
        Icons.swap_vert_circle_outlined,
        'Open Transfers',
        _openTransfers,
      ),
      (
        Icons.sync_rounded,
        'Open Sync center',
        _openSyncCenter,
      ),
      (
        Icons.notifications_none_rounded,
        'Open Notifications',
        _openNotifications,
      ),
      (
        Icons.create_new_folder_outlined,
        'New folder',
        () => _openFiles(FilesIntent.newFolder),
      ),
    ];

    await showNexaSheet<void>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final query = controller.text.trim();
          final needle = query.toLowerCase();
          final matches = commands
              .where(
                (command) =>
                    needle.isEmpty || command.$2.toLowerCase().contains(needle),
              )
              .toList(growable: false);

          return NexaSheetBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NexaSheetHeader(title: 'Quick actions', subtitle: 'Ctrl + K'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space16,
                  ),
                  child: NexaSearchField(
                    controller: controller,
                    hint: 'Search files or jump somewhere…',
                    autofocus: true,
                    onChanged: (_) => setSheetState(() {}),
                    onClear: () {
                      controller.clear();
                      setSheetState(() {});
                    },
                  ),
                ),
                const SizedBox(height: AppDimens.space8),
                if (query.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.search_rounded),
                    title: Text('Search for “$query”'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_pushRoute(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              SearchScreen(api: api, initialQuery: query),
                        ),
                      ));
                    },
                  ),
                for (final command in matches)
                  ListTile(
                    leading: Icon(command.$1),
                    title: Text(command.$2),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      command.$3();
                    },
                  ),
                if (matches.isEmpty && query.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppDimens.space24),
                    child: Text('No quick actions available.'),
                  ),
                const SizedBox(height: AppDimens.space8),
              ],
            ),
          );
        },
      ),
    );
    controller.dispose();
  }

  void _showMoreSheet() {
    if (_moreSheetOpen) {
      _closeMoreMenu();
      return;
    }
    setState(() => _moreSheetOpen = true);
  }

  void _closeMoreMenu() {
    if (!_moreSheetOpen) return;
    setState(() => _moreSheetOpen = false);
    if (_queuedSharedFiles.isNotEmpty &&
        !_shareSheetShowing &&
        !_deferShareProcessing) {
      unawaited(_processSharedFiles());
    }
  }

  void _openMoreAction(VoidCallback action) {
    _closeMoreMenu();
    action();
  }

  Widget _moreMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openMoreAction(onTap),
        borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
        child: SizedBox(
          height: 84,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: AppDimens.iconLarge,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppDimens.space8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyle.labelLarge.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreMenu() {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppDimens.radiusSheet);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.pageMargin,
          ),
          child: Material(
            color: scheme.surfaceContainerHigh,
            surfaceTintColor: Colors.transparent,
            elevation: AppDimens.elevationLevel3,
            shadowColor: scheme.shadow,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.space16,
                AppDimens.space12,
                AppDimens.space16,
                AppDimens.space16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'More',
                              style: AppTextStyle.titleLarge.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: AppDimens.space2),
                            Text(
                              'Tools and settings',
                              style: AppTextStyle.bodySmall.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                        onPressed: _closeMoreMenu,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.space8),
                  Row(
                    children: [
                      Expanded(
                        child: _moreMenuTile(
                          icon: Icons.document_scanner_outlined,
                          title: 'Scan',
                          onTap: () => unawaited(_pushRoute(
                            MaterialPageRoute<void>(
                              builder: (_) => ScannerScreen(api: api),
                            ),
                          )),
                        ),
                      ),
                      Expanded(
                        child: _moreMenuTile(
                          icon: Icons.cloud_upload_outlined,
                          title: 'Transfers',
                          onTap: _openTransfers,
                        ),
                      ),
                      Expanded(
                        child: _moreMenuTile(
                          icon: Icons.delete_outline_rounded,
                          title: 'Trash',
                          onTap: () => _goTo(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.space4),
                  Row(
                    children: [
                      Expanded(
                        child: _moreMenuTile(
                          icon: Icons.sync_rounded,
                          title: 'Sync',
                          onTap: _openSyncCenter,
                        ),
                      ),
                      Expanded(
                        child: _moreMenuTile(
                          icon: Icons.notifications_outlined,
                          title: 'Alerts',
                          onTap: _openNotifications,
                        ),
                      ),
                      Expanded(
                        child: _moreMenuTile(
                          icon: Icons.settings_outlined,
                          title: 'Settings',
                          onTap: () => _goTo(5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _sharedFileType(AndroidSharedFile file) {
    final mimeType = file.mimeType.toLowerCase();
    if (mimeType.startsWith('image/')) return 'Image';
    if (mimeType.startsWith('video/')) return 'Video';
    if (mimeType.startsWith('audio/')) return 'Audio';
    if (mimeType == 'application/pdf') return 'PDF document';
    if (mimeType.startsWith('text/')) return 'Text file';
    if (mimeType.startsWith('application/')) return 'Document';
    final subtype = mimeType.split('/').last;
    return subtype == 'octet-stream' ? 'File' : subtype.toUpperCase();
  }

  void _queueSharedFiles(List<AndroidSharedFile> files) {
    if (!mounted || files.isEmpty) return;
    final known = <String>{
      ..._activeSharedUris,
      ..._queuedSharedFiles.map((file) => file.uri),
    };
    _queuedSharedFiles.addAll(files.where((file) => known.add(file.uri)));
    if (!_shareSheetShowing && !_moreSheetOpen && !_deferShareProcessing) {
      unawaited(_processSharedFiles());
    }
  }

  void _retainSharedFiles(
    List<AndroidSharedFile> files, {
    String message = 'Import kept for later. Review it when ready.',
  }) {
    final known = _queuedSharedFiles.map((file) => file.uri).toSet();
    _queuedSharedFiles.addAll(files.where((file) => known.add(file.uri)));
    _deferShareProcessing = true;
    if (!mounted) return;
    _showPillNotice(
      message,
      actionLabel: 'Review',
      onAction: () {
        _deferShareProcessing = false;
        unawaited(_processSharedFiles());
      },
    );
  }

  Future<void> _processSharedFiles() async {
    if (!mounted ||
        _shareSheetShowing ||
        _deferShareProcessing ||
        _queuedSharedFiles.isEmpty) {
      return;
    }
    _closeMoreMenu();
    _shareSheetShowing = true;
    _deferShareProcessing = false;
    setState(() {});
    var files = List<AndroidSharedFile>.from(_queuedSharedFiles);
    _queuedSharedFiles.clear();
    _activeSharedUris.addAll(files.map((file) => file.uri));

    try {
      if (!mounted) return;
      final failed = files.where(
        (file) => file.stageError != null || file.size < 0,
      );
      if (failed.isNotEmpty) {
        final reason = failed.first.stageError;
        _retainSharedFiles(
          files,
          message: reason == null
              ? 'Could not prepare a shared file. Review to retry.'
              : 'Could not import ${failed.first.name}: $reason',
        );
        return;
      }

      final choice = await showNexaSheet<_SharedUploadChoice>(
        context,
        builder: (sheetContext) => NexaSheetBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NexaSheetHeader(
                title: 'Add to NexaDrive',
                subtitle:
                    '${files.length} ${files.length == 1 ? 'item' : 'items'} · '
                    'Original quality',
              ),
              for (final file in files.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space16,
                    vertical: AppDimens.space4,
                  ),
                  child: Row(
                    children: [
                      NexaFileGlyph(name: file.name, size: 22),
                      const SizedBox(width: AppDimens.space10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.subheadline,
                            ),
                            Text(
                              _sharedFileType(file),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.caption1.copyWith(
                                color: AppColors.labelSecondaryFor(
                                  Theme.of(sheetContext).brightness,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        Format.bytes(file.size),
                        style: AppTextStyle.caption1.copyWith(
                          color: AppColors.labelSecondaryFor(
                            Theme.of(sheetContext).brightness,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (files.length > 4)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space16,
                    vertical: AppDimens.space4,
                  ),
                  child: Text(
                    '+ ${files.length - 4} more items',
                    style: AppTextStyle.caption1.copyWith(
                      color: AppColors.labelSecondaryFor(
                        Theme.of(sheetContext).brightness,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppDimens.space8),
              NexaSheetAction(
                icon: Icons.cloud_upload_outlined,
                title: 'Upload as-is',
                subtitle: 'Save directly to My files',
                onTap: () =>
                    Navigator.pop(sheetContext, _SharedUploadChoice.root),
              ),
              NexaSheetAction(
                icon: Icons.create_new_folder_outlined,
                title: 'Create a folder',
                subtitle: 'Make a new folder, then upload into it',
                onTap: () => Navigator.pop(
                  sheetContext,
                  _SharedUploadChoice.createFolder,
                ),
              ),
              NexaSheetAction(
                icon: Icons.folder_open_rounded,
                title: 'Choose a folder',
                subtitle: 'Pick an existing destination in your cloud',
                onTap: () => Navigator.pop(
                  sheetContext,
                  _SharedUploadChoice.chooseFolder,
                ),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (choice == null) {
        _retainSharedFiles(files);
        return;
      }

      var destination = '';
      if (choice == _SharedUploadChoice.createFolder) {
        final controller = TextEditingController();
        final name = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Create upload folder'),
            content: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Folder name',
                hintText: 'e.g. Shared photos',
              ),
              onSubmitted: (value) =>
                  Navigator.pop(dialogContext, value.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, controller.text.trim()),
                child: const Text('Create'),
              ),
            ],
          ),
        );
        controller.dispose();
        final safeName = name?.trim() ?? '';
        if (safeName.isEmpty) {
          _retainSharedFiles(files);
          return;
        }
        if (safeName == '.' ||
            safeName == '..' ||
            safeName.contains('/') ||
            safeName.contains('\\')) {
          throw const FormatException(
            'Enter a single folder name without slashes.',
          );
        }
        try {
          await api.createFolder(safeName);
        } on ApiException catch (error) {
          if (error.status != 409) rethrow;
          // An existing destination folder is a valid upload target.
        }
        destination = safeName;
      } else if (choice == _SharedUploadChoice.chooseFolder) {
        final selected = await FolderPicker.pick(
          context,
          api: api,
          title: 'Upload to folder',
        );
        if (selected == null) {
          _retainSharedFiles(files);
          return;
        }
        destination = selected;
      }

      final sources = files
          .map(
            (file) => UploadSource(
              path: file.localPath ?? file.uri,
              sourceUri: file.localPath == null ? file.uri : null,
              name: file.name,
              size: file.size,
              temporary: file.localPath != null,
            ),
          )
          .toList(growable: false);
      final manager = UploadManager.current;
      await manager.enqueueAll(sources, destination);
      await AndroidShareIntents.acknowledge(files);
      if (mounted) {
        _toast(
          '${sources.length} ${sources.length == 1 ? 'file' : 'files'} '
          'queued for upload',
        );
        _openTransfers();
      }
    } catch (error) {
      _retainSharedFiles(
        files,
        message: 'Import was not queued: $error. Review to retry.',
      );
    } finally {
      _activeSharedUris.removeAll(files.map((file) => file.uri));
      _shareSheetShowing = false;
      if (mounted) setState(() {});
      if (mounted && _queuedSharedFiles.isNotEmpty && !_deferShareProcessing) {
        unawaited(_processSharedFiles());
      }
    }
  }

  Future<void> logout() async {
    await BackgroundTransferService.cancel();
    await api.logout();
    await _purgeLocalCaches();
    if (!mounted) return;
    unawaited(_resetToRoute(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(session: widget.session),
      ),
    ));
  }

  /// Removes everything this account cached on the device: thumbnails, any
  /// legacy media cache and decoded frames. A shared device must not hand the
  /// next account another user's images.
  Future<void> _purgeLocalCaches() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    try {
      await (await ThumbnailCache.open()).clear();
    } catch (_) {}
    try {
      await MediaCache.purgeLegacy();
    } catch (_) {}
  }

  @override
  void dispose() {
    AndroidShareIntents.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _queueTimer?.cancel();
    _transferEvents?.cancel();
    _transferNoticeTimer?.cancel();
    _transferStripHoldTimer?.cancel();
    if (_observedRoute != null) {
      AppShell.routeObserver.unsubscribe(this);
    }
    _uploads.removeListener(_refreshTransferStrip);
    // The app is no longer in the foreground, so the background worker may
    // take over the queue.
    _uploads.releaseForeground();
    updateController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new session or injected client means every destination must bind to
    // fresh dependencies. The controller belongs to this State, but keep it in
    // each page's inputs so a future replacement cannot serve stale widgets.
    if (!identical(oldWidget.session, widget.session) ||
        !identical(oldWidget.api, widget.api)) {
      _invalidatePages();
    }
  }

  /// One widget per destination, constructed on first build and reused.
  ///
  /// The shell rebuilds often (transfer strip, sheets, toasts). Re-creating six
  /// screens for every one of those frames — and again on every tab change —
  /// made taps feel laggy. Identical widget instances let Flutter's
  /// `updateChild` skip the page entirely, while visited destinations keep
  /// their [State] in the [IndexedStack].
  final List<Widget?> _pageCache = List<Widget?>.filled(_pageCount, null);
  final List<_PageInputs?> _pageInputs =
      List<_PageInputs?>.filled(_pageCount, null);
  Object? _pageController;

  void _invalidatePages() {
    for (var i = 0; i < _pageCount; i++) {
      _pageCache[i] = null;
      _pageInputs[i] = null;
    }
  }

  Widget _createPage(int index) {
    final page = switch (index) {
      0 => HomeScreen(
          session: widget.session,
          api: api,
          onNavigate: _goTo,
          onFilesIntent: _openFiles,
        ),
      1 => FilesScreen(
          api: api,
          onBackAtRoot: () => _goTo(0),
          intent: _filesIntent,
          onIntentHandled: () {
            if (_filesIntent != null) setState(() => _filesIntent = null);
          },
        ),
      2 => SharedScreen(api: api),
      3 => PhotosScreen(
          api: api,
          session: widget.session,
        ),
      4 => TrashScreen(api: api),
      5 => SettingsScreen(
          session: widget.session,
          api: api,
          updateController: updateController,
          onLogout: logout,
          onOpenSync: _openSyncCenter,
          onOpenTransfers: _openTransfers,
          onOpenNotifications: _openNotifications,
        ),
      _ => const SizedBox.shrink(),
    };
    // Each page paints into its own layer, so shell overlays and tab reveals
    // never force a visited screen to repaint.
    return RepaintBoundary(child: page);
  }

  /// The shell's destinations, in navigation order.
  ///
  /// Only destinations whose inputs changed are reconstructed; My files is
  /// rebuilt when [FilesIntent] changes and nowhere else.
  List<Widget> _buildPages() {
    // The controller is State-owned, but a replacement must not leave cached
    // destinations bound to the old one.
    if (!identical(_pageController, updateController)) {
      _invalidatePages();
      _pageController = updateController;
    }
    final inputs = <_PageInputs>[
      _PageInputs(session: widget.session, api: api),
      _PageInputs(api: api, intent: _filesIntent),
      _PageInputs(api: api),
      _PageInputs(session: widget.session, api: api),
      _PageInputs(api: api),
      _PageInputs(
        session: widget.session,
        api: api,
        controller: updateController,
      ),
    ];
    return List<Widget>.generate(_pageCount, (i) {
      final cached = _pageCache[i];
      final previous = _pageInputs[i];
      if (cached != null && previous != null && previous.sameAs(inputs[i])) {
        return cached;
      }
      final page = _createPage(i);
      _pageCache[i] = page;
      _pageInputs[i] = inputs[i];
      return page;
    }, growable: false);
  }

  Widget _buildPillNotice() {
    final notice = _pillNotice!;
    return NexaPillNotice(
      key: ValueKey(notice.id),
      message: notice.message,
      actionLabel: notice.actionLabel,
      onAction: notice.onAction,
      onDismissed: () => _dismissPillNotice(notice.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 900;
    final pages = _buildPages();

    // Desktop: persistent sidebar rail.
    if (desktop) {
      return PopScope(
          canPop: index == 0 && !_moreSheetOpen,
          onPopInvokedWithResult: (didPop, _) => _handleSystemBack(didPop),
          child: Scaffold(
            body: CallbackShortcuts(
              bindings: {
                SingleActivator(
                  LogicalKeyboardKey.keyK,
                  control: true,
                ): _showCommandPalette,
                SingleActivator(
                  LogicalKeyboardKey.keyK,
                  meta: true,
                ): _showCommandPalette,
                const SingleActivator(LogicalKeyboardKey.escape):
                    _closeMoreMenu,
              },
              child: Focus(
                autofocus: true,
                child: Row(
                  children: [
                    SideNavigation(
                      index: index,
                      onSelected: _goTo,
                      onSync: _openSyncCenter,
                      onTransfers: _openTransfers,
                      onNotifications: _openNotifications,
                    ),
                    Expanded(
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          padding: MediaQuery.paddingOf(context).copyWith(
                            bottom: _transferStripVisible
                                ? _transferStripSpace(AppDimens.space16)
                                : MediaQuery.paddingOf(context).bottom,
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom: _transferStripVisible
                                      ? _transferStripSpace(AppDimens.space16)
                                      : 0,
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: AppDimens.contentMaxWidth,
                                  ),
                                  child: _PageHost(
                                    index: index,
                                    visited: _visited,
                                    pages: pages,
                                  ),
                                ),
                              ),
                            ),
                            if (_transferStripVisible)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: AppDimens.space16,
                                child: _buildTransferStrip(maxWidth: 460),
                              ),
                            if (_pillNotice != null && !_moreSheetOpen)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: _transferStripVisible
                                    ? _transferStripSpace(AppDimens.space16)
                                    : AppDimens.space16,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: AppDimens.bottomNavMaxWidth,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppDimens.space12,
                                      ),
                                      child: _buildPillNotice(),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ));
    }

    // Mobile: the page fills the screen behind an independently positioned,
    // floating tonal pill. The shell exposes bottom clearance through MediaQuery
    // so scrollable content can reach a position above the pill without painting
    // a full-width navigation sheet.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final transferStripSpace =
        _transferStripVisible ? _transferStripSpace(AppDimens.space8) : 0.0;
    final pillInset = AppDimens.space12 * 2 +
        AppDimens.bottomNavHeight +
        bottomInset +
        18 +
        transferStripSpace;

    return PopScope(
        canPop: index == 0 && !_moreSheetOpen,
        onPopInvokedWithResult: (didPop, _) => _handleSystemBack(didPop),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _closeMoreMenu,
          },
          child: Scaffold(
            // This is the app canvas, not a navigation bar: the page fills the
            // screen and paints behind the independently positioned pill.
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: Stack(
              fit: StackFit.expand,
              children: [
                ExcludeSemantics(
                  excluding: _moreSheetOpen,
                  child: MediaQuery(
                    // Keep the page at full height so its background/content can
                    // continue behind the pill. This inset is a scroll-clearance
                    // hint only; the pill itself remains the only bottom overlay.
                    data: MediaQuery.of(context).copyWith(
                      padding: MediaQuery.paddingOf(context).copyWith(
                        bottom: pillInset,
                      ),
                    ),
                    child: _PageHost(
                      index: index,
                      visited: _visited,
                      pages: pages,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppDimens.space10 +
                      bottomInset +
                      AppDimens.bottomNavHeight +
                      AppDimens.space8,
                  child: ExcludeSemantics(
                    excluding: _moreSheetOpen,
                    child: _buildTransferStrip(),
                  ),
                ),
                if (_moreSheetOpen) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _closeMoreMenu,
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.scrim.withValues(
                              alpha: 0.32,
                            ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: AppDimens.bottomNavHeight +
                        AppDimens.space10 * 2 +
                        bottomInset +
                        28,
                    child: Focus(
                      autofocus: true,
                      onKeyEvent: (node, event) {
                        final isEscape =
                            event is KeyDownEvent || event is KeyRepeatEvent;
                        if (!isEscape ||
                            event.logicalKey != LogicalKeyboardKey.escape) {
                          return KeyEventResult.ignored;
                        }
                        _closeMoreMenu();
                        return KeyEventResult.handled;
                      },
                      child: Semantics(
                        scopesRoute: true,
                        namesRoute: true,
                        explicitChildNodes: true,
                        label: 'More tools and settings',
                        child: _buildMoreMenu(),
                      ),
                    ),
                  ),
                ],
                if (!_shareSheetShowing)
                  Positioned(
                    left: 0,
                    right: 0,
                    // Keep the pill separate from the system gesture area; the pill's
                    // own surface, outline, and shadow create its floating appearance.
                    bottom: AppDimens.space10 + bottomInset,
                    child: ExcludeSemantics(
                      excluding: _moreSheetOpen,
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AppDimens.bottomNavMaxWidth,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppDimens.space12,
                              ),
                              child: _pillNotice != null
                                  ? _buildPillNotice()
                                  : NexaBottomNav(
                                      currentIndex: index >= 4 ? 4 : index,
                                      onTap: (value) {
                                        if (value == 4) {
                                          _showMoreSheet();
                                        } else {
                                          _goTo(value);
                                        }
                                      },
                                      items: NexaBottomNavItems.primary,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ));
  }
}

enum _SharedUploadChoice { root, createFolder, chooseFolder }

/// One transient in-pill message. A monotonically increasing id gives each
/// notice a fresh key so back-to-back messages restart the auto-dismiss timer.
class _PillNotice {
  const _PillNotice({
    required this.id,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final int id;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Inputs a cached destination was built against. Services and the session are
/// compared by identity; the one-shot Files intent is compared by value.
class _PageInputs {
  const _PageInputs({
    this.session,
    this.api,
    this.controller,
    this.intent,
  });

  final Object? session;
  final Object? api;
  final Object? controller;
  final FilesIntent? intent;

  bool sameAs(_PageInputs other) =>
      identical(session, other.session) &&
      identical(api, other.api) &&
      identical(controller, other.controller) &&
      intent == other.intent;
}

/// Holds every visited destination in one [IndexedStack].
///
/// Navigation preserves each page's state: My files keeps the folder you were
/// in, Photos keeps its scroll offset, and returning to a tab does not re-issue
/// its request. Unvisited destinations render nothing until first opened.
///
/// A tab switch reveals the destination with a short scale + slide + fade
/// driven by [AppMotion.fluid]. The reveal starts on the frame of the tap, can
/// be redirected by another tap without flashing back to transparent, and is
/// skipped entirely for reduced motion. The cached page widgets are reused, so
/// no scroll position or in-flight request is lost.
///
/// The page host keeps normal content below the status bar. The shell passes
/// bottom navigation clearance through MediaQuery, allowing scrollable pages
/// to scroll their last items above the pill while the page still paints behind it.
class _PageHost extends StatefulWidget {
  final int index;
  final Set<int> visited;
  final List<Widget> pages;

  const _PageHost({
    required this.index,
    required this.visited,
    required this.pages,
  });

  @override
  State<_PageHost> createState() => _PageHostState();
}

class _PageHostState extends State<_PageHost>
    with SingleTickerProviderStateMixin {
  // Starts settled so the first frame paints at full opacity. A tab change
  // replays a short reveal; rapid taps continue from the value on screen.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: AppMotion.fast,
    value: 1,
  );

  late final Animation<double> _fluid = _reveal.drive(
    CurveTween(curve: AppMotion.fluid),
  );

  // Begin partially revealed so the destination is legible on the first frame;
  // the overshoot is clamped for opacity below.
  late final Animation<double> _opacity = _ClampedOpacity(
    Tween<double>(begin: 0.35, end: 1).animate(_fluid),
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 0.985,
    end: 1,
  ).animate(_fluid);

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.008),
    end: Offset.zero,
  ).animate(_fluid);

  @override
  void didUpdateWidget(covariant _PageHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _startReveal();
  }

  void _startReveal() {
    if (AppMotion.reducedMotion(context)) {
      _reveal
        ..stop()
        ..value = 1;
      return;
    }
    // Interrupt from the presentation value, never from the target: a second
    // tap mid-reveal keeps the progress already made instead of flashing.
    final from = _reveal.value >= 1 ? 0.0 : _reveal.value;
    _reveal
      ..stop()
      ..value = from
      ..forward();
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stack = IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.pages.length; i++)
          if (widget.visited.contains(i))
            widget.pages[i]
          else
            const SizedBox.shrink(),
      ],
    );

    if (AppMotion.reducedMotion(context)) {
      return SafeArea(top: true, bottom: false, child: stack);
    }

    return SafeArea(
      top: true,
      bottom: false,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _offset,
          child: ScaleTransition(scale: _scale, child: stack),
        ),
      ),
    );
  }
}

/// Keeps [AppMotion.fluid]'s tiny overshoot out of [FadeTransition], whose
/// opacity must stay in 0..1.
class _ClampedOpacity extends Animation<double>
    with AnimationWithParentMixin<double> {
  const _ClampedOpacity(this.parent);

  @override
  final Animation<double> parent;

  @override
  double get value => parent.value.clamp(0.0, 1.0);
}
