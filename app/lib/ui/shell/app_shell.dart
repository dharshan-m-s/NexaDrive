import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../core/design/app_motion.dart';
import '../../../services/api.dart';
import '../../../services/session.dart';
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
/// Mobile uses a floating Liquid Glass dock; desktop uses a persistent sidebar
/// rail. On wide screens a transfer status strip surfaces the offline queue.
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

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int index = 0;
  late final Api api;
  late final UpdateController updateController;
  Timer? _queueTimer;
  bool _handlingExpiredSession = false;
  bool _moreSheetOpen = false;
  bool _shareSheetShowing = false;
  bool _photosSelecting = false;
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
    setState(() {
      index = value;
      _visited.add(value);
    });
  }

  void _handleSystemBack(bool didPop) {
    if (!didPop && index != 0 && index != 1) _goTo(0);
  }

  /// Opens My files and asks it to start [intent], so a Home shortcut performs
  /// the action it names rather than just navigating.
  void _openFiles(FilesIntent intent) {
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
    UploadManager.current
      ..attach(api)
      ..claimForeground();
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
      MaterialPageRoute(builder: (_) => const TransfersScreen()),
    );
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
    final brightness = Theme.of(context).brightness;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openMoreAction(onTap),
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 82,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accentContainerFor(brightness),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: AppColors.accentTextFor(brightness)
                        .withValues(alpha: 0.11),
                  ),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: AppColors.accentTextFor(brightness),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyle.caption1.copyWith(
                  color: AppColors.labelPrimaryFor(brightness),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreMenu() {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final accent = AppColors.accentFor(brightness);
    return Stack(
      fit: StackFit.expand,
      children: [
        // The local ambient reflection sits behind the lens, so the optical
        // edge has real scene colour to bend even over a near-black page.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.1, 0.55),
                  radius: 0.82,
                  colors: [
                    accent.withValues(alpha: dark ? 0.10 : 0.075),
                    Colors.transparent,
                  ],
                  stops: const [0, 1],
                ),
              ),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pageMargin,
              ),
              child: NexaLiquidGlass(
                borderRadius: BorderRadius.circular(28),
                blurSigma: 2.4,
                tintOpacity: dark ? 0.15 : 0.115,
                refractionHeight: 22,
                refractionAmount: -44,
                depthEffect: 1.0,
                chromaticDispersion: 2.0,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                showShadow: true,
                showHighlight: true,
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
                                style: AppTextStyle.title3.copyWith(
                                  color: AppColors.labelPrimaryFor(brightness),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tools and settings',
                                style: AppTextStyle.caption1.copyWith(
                                  color: AppColors.labelSecondaryFor(brightness),
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _moreMenuTile(
                            icon: Icons.document_scanner_outlined,
                            title: 'Scan',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ScannerScreen(api: api),
                              ),
                            ),
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
                    const SizedBox(height: 4),
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
      ],
    );
  }

  IconData _sharedFileIcon(AndroidSharedFile file) {
    final mime = file.mimeType.toLowerCase();
    final name = file.name.toLowerCase();
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('video/')) return Icons.videocam_outlined;
    if (mime.startsWith('audio/')) return Icons.audio_file_outlined;
    if (mime == 'application/pdf' || name.endsWith('.pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (mime.startsWith('text/')) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
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
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'Review',
            onPressed: () {
              _deferShareProcessing = false;
              unawaited(_processSharedFiles());
            },
          ),
        ),
      );
  }

  Future<void> _processSharedFiles() async {
    if (!mounted ||
        _shareSheetShowing ||
        _deferShareProcessing ||
        _queuedSharedFiles.isEmpty) {
      return;
    }
    _shareSheetShowing = true;
    _deferShareProcessing = false;
    setState(() {});
    var files = List<AndroidSharedFile>.from(_queuedSharedFiles);
    _queuedSharedFiles.clear();
    _activeSharedUris.addAll(files.map((file) => file.uri));

    try {
      files = await AndroidShareIntents.stage(files);
      if (!mounted) return;
      final failed = files.where(
        (file) => file.localPath == null || file.stageError != null,
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
                      Icon(_sharedFileIcon(file), size: 19),
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
              path: file.localPath!,
              name: file.name,
              size: file.size,
              temporary: true,
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
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(session: widget.session)),
      (_) => false,
    );
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
    // The app is no longer in the foreground, so the background worker may
    // take over the queue.
    UploadManager.current.releaseForeground();
    updateController.dispose();
    super.dispose();
  }

  /// The shell's destinations, in navigation order.
  ///
  /// These are rebuilt on each shell frame rather than cached, because a
  /// destination's parameters (My files' pending intent) must be able to
  /// update. State is still preserved: each index always holds the same widget
  /// type, so Flutter reuses the existing element instead of recreating it.
  List<Widget> _buildPages() => <Widget>[
        HomeScreen(
          session: widget.session,
          api: api,
          onNavigate: _goTo,
          onFilesIntent: _openFiles,
        ),
        FilesScreen(
          api: api,
          onBackAtRoot: () => _goTo(0),
          intent: _filesIntent,
          onIntentHandled: () {
            if (_filesIntent != null) setState(() => _filesIntent = null);
          },
        ),
        SharedScreen(api: api),
        PhotosScreen(
          api: api,
          session: widget.session,
          onSelectionChanged: (selecting) {
            if (_photosSelecting != selecting) {
              setState(() => _photosSelecting = selecting);
            }
          },
        ),
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 900;
    final pages = _buildPages();

    // Desktop: persistent sidebar rail.
    if (desktop) {
      return PopScope(
          canPop: index == 0,
          onPopInvokedWithResult: (didPop, _) => _handleSystemBack(didPop),
          child: Scaffold(
            body: Row(
              children: [
                SideNavigation(
                  index: index,
                  onSelected: _goTo,
                  onSync: _openSyncCenter,
                  onTransfers: _openTransfers,
                  onNotifications: _openNotifications,
                ),
                Expanded(
                  child: Center(
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
              ],
            ),
          ));
    }

    // Mobile: the page fills the screen behind an independently positioned,
    // floating glass dock. The shell exposes bottom clearance through MediaQuery
    // so scrollable content can reach a position above the pill without painting
    // a full-width navigation sheet.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final pillInset =
        AppDimens.space12 * 2 + AppDimens.bottomNavHeight + bottomInset + 18;

    return PopScope(
        canPop: index == 0,
        onPopInvokedWithResult: (didPop, _) => _handleSystemBack(didPop),
        child: Scaffold(
          // This is the app canvas, not a navigation bar: the page fills the
          // screen and paints behind the independently positioned pill.
          backgroundColor: AppColors.backgroundFor(
            Theme.of(context).brightness,
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              MediaQuery(
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
              if (_moreSheetOpen) ...[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closeMoreMenu,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.055),
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
                  child: _buildMoreMenu(),
                ),
              ],
              if (!_shareSheetShowing && !(index == 3 && _photosSelecting))
                Positioned(
                  left: 0,
                  right: 0,
                  // Keep the pill separate from the system gesture area; the pill's
                  // own surface, outline, and shadow create its floating appearance.
                  bottom: AppDimens.space10 + bottomInset,
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimens.pageMargin,
                          ),
                          child: NexaBottomNav(
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
            ],
          ),
        ));
  }
}

enum _SharedUploadChoice { root, createFolder, chooseFolder }

/// Holds every visited destination in one [IndexedStack].
///
/// Navigation preserves each page's state: My files keeps the folder you were
/// in, Photos keeps its scroll offset, and returning to a tab does not re-issue
/// its request. Unvisited destinations render nothing, so they cost nothing
/// until first opened.
///
/// A tab switch reveals the destination with a short fade-through rather than a
/// hard cut. The [IndexedStack] itself is never rebuilt, so the incoming page
/// fades in over the one it replaces without losing scroll position or an
/// in-flight request. Reduced motion skips the fade entirely.
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
  // Drives the fade-through. Starts settled so the first frame paints the shell
  // at full opacity; every later index change replays it once.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: AppMotion.fast,
    value: 1,
  );

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _reveal,
    curve: AppMotion.fadeCurve,
  );

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.012),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(parent: _reveal, curve: AppMotion.standardCurve),
  );

  @override
  void didUpdateWidget(covariant _PageHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _reveal.forward(from: 0);
    }
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
        child: SlideTransition(position: _offset, child: stack),
      ),
    );
  }
}
