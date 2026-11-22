import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/sync_service.dart';
import '../../widgets/nexa_components.dart';

/// Sync Center.
///
/// Answers, in order: is sync on? which folder? when did it last run? what is
/// happening now? are there conflicts? which devices are linked? — and then
/// lets the user act on each answer.
class SyncCenterScreen extends StatefulWidget {
  final Api api;
  const SyncCenterScreen({super.key, required this.api});

  @override
  State<SyncCenterScreen> createState() => _SyncCenterScreenState();
}

class _SyncCenterScreenState extends State<SyncCenterScreen> {
  bool _loading = true;
  String? _localLoadError;
  String? _deviceLoadError;
  bool _devicesLoading = false;
  String? _folderPath;
  List<Map<String, String>> _androidFolders = [];
  DateTime? _lastSyncAt;
  String? _thisDeviceId;
  List<Map<String, dynamic>> _devices = [];
  int _conflicts = 0;
  SyncResult? _lastResult;
  bool _syncing = false;
  String _progress = '';

  bool get _syncSupported =>
      Platform.isAndroid ||
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init({bool devicesOnly = false}) async {
    if (devicesOnly && _localLoadError == null) {
      // A device-list retry must not take the folder settings off screen.
      setState(() => _devicesLoading = true);
      try {
        final devices = await widget.api.syncDevices();
        if (!mounted) return;
        setState(() {
          _devices = devices;
          _deviceLoadError = null;
          _devicesLoading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _deviceLoadError = _friendlyError(e,
              verb: 'load', subject: 'the linked device list');
          _devicesLoading = false;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _localLoadError = null;
      _deviceLoadError = null;
    });
    final manager = SyncManager(widget.api);

    String? folder;
    List<Map<String, String>> androidFolders = <Map<String, String>>[];
    DateTime? lastSync;
    String? deviceId;
    var conflicts = 0;
    List<Map<String, dynamic>> devices = <Map<String, dynamic>>[];
    Object? localError;
    Object? deviceError;

    // Local state and server state are independent: a failed device list must
    // never blank the screen, and a failed local read must never leave the page
    // spinning forever because the fallback read failed a second time.
    try {
      folder = await manager.folder();
      if (Platform.isAndroid) androidFolders = await manager.androidFolders();
      lastSync = await manager.lastSyncAt();
      deviceId = await manager.deviceId();
      conflicts = await manager.conflictCount();
    } catch (e) {
      localError = e;
    }
    try {
      devices = await widget.api.syncDevices();
    } catch (e) {
      deviceError = e;
    }

    if (!mounted) return;
    setState(() {
      _folderPath = folder;
      _androidFolders = androidFolders;
      _lastSyncAt = lastSync;
      _thisDeviceId = deviceId;
      _conflicts = conflicts;
      _devices = devices;
      _loading = false;
      if (localError != null) {
        _localLoadError = _friendlyError(
          localError,
          verb: 'load',
          subject: 'your sync settings',
        );
      }
      if (deviceError != null) {
        _deviceLoadError = _friendlyError(
          deviceError,
          verb: 'load',
          subject: 'the linked device list',
        );
      }
    });
  }

  Future<void> _chooseFolder() async {
    try {
      final manager = SyncManager(widget.api);
      final path = await manager.pickAndSetFolder();
      if (path == null) return;
      final folders = Platform.isAndroid
          ? await manager.androidFolders()
          : <Map<String, String>>[];
      final label = await manager.folder();
      if (mounted) {
        setState(() {
          _folderPath = label;
          _androidFolders = folders;
        });
        _toast('Added “$path” to phone backup');
      }
    } catch (error) {
      if (mounted) {
        _toast(_friendlyError(error,
            verb: 'save', subject: 'the selected folder'));
      }
    }
  }

  Future<void> _removeAndroidFolder(Map<String, String> folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.folder_off_outlined, color: scheme.error),
          title: const Text('Remove backup folder?'),
          content: Text(
            'NexaDrive will stop scanning “${folder['name']}”. Files already uploaded remain in My Files.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              child: const Text('Remove folder'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      final manager = SyncManager(widget.api);
      await manager.removeAndroidFolder(folder['uri']!);
      final folders = await manager.androidFolders();
      final label = await manager.folder();
      if (mounted) {
        setState(() {
          _androidFolders = folders;
          _folderPath = label;
        });
      }
    } catch (error) {
      if (mounted) {
        _toast(_friendlyError(error,
            verb: 'update', subject: 'your backup folders'));
      }
    }
  }

  Future<void> _runSync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _progress = 'Preparing selected folders…';
      _lastResult = null;
    });
    final manager = SyncManager(widget.api);
    SyncResult result;
    try {
      result = await manager.sync(onProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      });
    } catch (error) {
      result = SyncResult(
        errors: 1,
        error: _friendlyError(error, verb: 'finish', subject: 'the last sync'),
      );
    }

    var conflicts = _conflicts;
    DateTime? lastSync = _lastSyncAt;
    var deviceId = _thisDeviceId;
    var folders = _androidFolders;
    var folderLabel = _folderPath;
    try {
      conflicts = await manager.conflictCount();
      lastSync = await manager.lastSyncAt();
      deviceId = await manager.deviceId();
      if (Platform.isAndroid) {
        folders = await manager.androidFolders();
        folderLabel = await manager.folder();
      }
    } catch (_) {
      // The upload result is still authoritative even if refreshing local
      // metadata fails.
    }
    List<Map<String, dynamic>> devices = _devices;
    String? deviceLoadError;
    try {
      devices = await widget.api.syncDevices();
    } catch (e) {
      deviceLoadError =
          _friendlyError(e, verb: 'load', subject: 'the linked device list');
    }
    if (!mounted) return;
    setState(() {
      _lastResult = result;
      _conflicts = conflicts;
      _lastSyncAt = lastSync;
      _thisDeviceId = deviceId;
      _devices = devices;
      _deviceLoadError = deviceLoadError;
      _androidFolders = folders;
      _folderPath = folderLabel;
      _syncing = false;
      _progress = '';
    });
    if (result.error != null) {
      _toast(result.error!);
    } else if (result.uploaded > 0 || result.errors > 0) {
      final errors = result.errors == 1 ? '1 error' : '${result.errors} errors';
      _toast('Backup finished: ${result.uploaded} uploaded, $errors');
    } else {
      _toast('All selected folders are up to date');
    }
  }

  Future<void> _clearFolder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.sync_disabled_rounded, color: scheme.error),
          title: const Text('Stop syncing this folder?'),
          content: const Text(
            'Files already synchronized stay where they are. NexaDrive simply '
            'stops watching this folder for changes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Stop syncing'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await SyncManager(widget.api).clearFolder();
    if (mounted) setState(() => _folderPath = null);
  }

  Future<void> _renameDevice(Map<String, dynamic> device) async {
    final controller = TextEditingController(
      text: device['name']?.toString() ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.edit_outlined, color: scheme.primary),
          title: const Text('Rename device'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 64,
            decoration: const InputDecoration(labelText: 'Device name'),
            onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    try {
      await widget.api.renameSyncDevice(device['id'].toString(), name);
      // A rename of this machine must also stick locally, otherwise the next
      // sync would push the old name back.
      if (device['id'] == _thisDeviceId) {
        await SyncManager(widget.api).setDeviceName(name);
      }
      if (mounted) {
        setState(() {
          final index = _devices.indexWhere((d) => d['id'] == device['id']);
          if (index >= 0) _devices[index] = {..._devices[index], 'name': name};
        });
      }
    } catch (e) {
      if (mounted) {
        _toast(_friendlyError(e, verb: 'update', subject: 'the linked device'));
      }
    }
  }

  Future<void> _revokeDevice(Map<String, dynamic> device) async {
    final isThisDevice = device['id'] == _thisDeviceId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.link_off_rounded, color: scheme.error),
          title: const Text('Unlink device'),
          content: Text(
            isThisDevice
                ? 'This is the device you are using. Unlinking it stops sync here '
                    'until the next run re-registers it. Continue?'
                : '“${device['name']}” will stop syncing until it links again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              child: const Text('Unlink'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await widget.api.revokeSyncDevice(device['id'].toString());
      if (mounted) {
        setState(() => _devices.removeWhere((d) => d['id'] == device['id']));
        _toast('Device unlinked');
      }
    } catch (e) {
      if (mounted) {
        _toast(_friendlyError(e, verb: 'unlink', subject: 'that device'));
      }
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _resolveStatus();
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: NexaPage(
          title: 'Sync center',
          subtitle: _loading ? null : status.summary,
          leading: const NexaBackButton(),
          headerAction: IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _init,
            icon: const Icon(Icons.refresh_rounded),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageMargin,
            0,
            AppDimens.pageMargin,
            AppDimens.space24,
          ),
          body: NexaStateSwitcher(
            stateKey: ValueKey(
              _loading
                  ? 'loading'
                  : _localLoadError != null
                      ? 'settings-error'
                      : 'content',
            ),
            child: _body(status, scheme),
          ),
        ),
      ),
    );
  }

  Widget _body(_SyncStatus status, ColorScheme scheme) {
    if (_loading) {
      return const NexaLoadingBlock(label: 'Checking your folders…');
    }
    if (_localLoadError != null) {
      return RefreshIndicator(
        onRefresh: _init,
        child: NexaErrorStateFullScreen(
          title: 'We couldn’t load your sync settings',
          message: '$_localLoadError Nothing has changed on this device.',
          actionLabel: 'Retry',
          onAction: _init,
          icon: Icons.cloud_off_outlined,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _init,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: AppDimens.space8),
        children: [
          // Decisions come first: a count in the header is only useful if the
          // files waiting on the user are immediately within reach.
          if (_conflicts > 0) ...[
            _ConflictCard(
              key: ValueKey(
                'conflicts-$_conflicts-${_lastSyncAt?.millisecondsSinceEpoch ?? 0}',
              ),
              api: widget.api,
              onResolved: _init,
            ),
            const SizedBox(height: AppDimens.space16),
          ],
          _StatusCard(status: status, showProgress: _syncing),
          if (Platform.isAndroid) ...[
            const SizedBox(height: AppDimens.space16),
            const _Notice(
              icon: Icons.info_outline_rounded,
              title: 'One-way phone folder backup',
              body: 'Add multiple phone folders. Sync now uploads every file '
                  'and subfolder from each one, then uploads new or changed '
                  'files on later runs. Phone files are never deleted.',
            ),
          ],
          const SizedBox(height: AppDimens.space24),
          _SectionLabel(Platform.isAndroid ? 'Phone folders' : 'Synced folder'),
          const SizedBox(height: AppDimens.space8),
          if (Platform.isAndroid)
            _AndroidFoldersCard(
              folders: _androidFolders,
              onChoose: _chooseFolder,
              onRemove: _removeAndroidFolder,
            )
          else
            _FolderCard(
              folder: _folderPath,
              onChoose: _chooseFolder,
              onClear: _clearFolder,
            ),
          const SizedBox(height: AppDimens.space24),
          SizedBox(
            height: AppDimens.touchTargetLarge,
            child: FilledButton.icon(
              onPressed: _syncing || _folderPath == null || !_syncSupported
                  ? null
                  : _runSync,
              icon: _syncing
                  ? SizedBox(
                      width: AppDimens.iconSmall,
                      height: AppDimens.iconSmall,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(_syncing ? 'Syncing…' : 'Sync now'),
            ),
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: AppDimens.space16),
            _LastRunCard(result: _lastResult!, onRetry: _runSync),
          ],
          const SizedBox(height: AppDimens.space28),
          const _SectionLabel('Linked devices'),
          const SizedBox(height: AppDimens.space4),
          Text(
            'Devices that have synced with this account.',
            style: AppTextStyle.bodySmall.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppDimens.space12),
          if (_deviceLoadError != null)
            _ActionNotice(
              icon: Icons.cloud_off_outlined,
              title: 'Linked devices are unavailable',
              body: '$_deviceLoadError Your folder settings are still here.',
              actionLabel: 'Retry',
              onAction: _retryDevices,
              loading: _devicesLoading,
            )
          else if (_devices.isEmpty)
            NexaEmptyState(
              icon: Icons.devices_other_rounded,
              title: 'No linked devices yet',
              hint: 'Run a sync from a computer and it will appear here.',
              actionLabel: 'Check again',
              actionIcon: Icons.refresh_rounded,
              onAction: _init,
            )
          else
            for (final device in _devices)
              Padding(
                padding: const EdgeInsets.only(bottom: AppDimens.space8),
                child: _DeviceRow(
                  device: device,
                  isThisDevice: device['id'] == _thisDeviceId,
                  onRename: () => _renameDevice(device),
                  onRevoke: () => _revokeDevice(device),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _retryDevices() => _init(devicesOnly: true);

  /// The header and the status card read the same resolver, so they can never
  /// disagree about what sync is doing right now.
  _SyncStatus _resolveStatus() {
    if (_loading) {
      return const _SyncStatus(
        summary: 'Checking your sync…',
        title: 'Checking your sync…',
        body: 'Looking over your folders and recent activity.',
        icon: Icons.sync_rounded,
        tone: _SyncTone.primary,
      );
    }
    if (_localLoadError != null) {
      return const _SyncStatus(
        summary: 'Sync settings unavailable',
        title: 'We couldn’t load your sync settings',
        body: 'Nothing has changed on this device. Try again in a moment.',
        icon: Icons.cloud_off_outlined,
        tone: _SyncTone.warning,
      );
    }
    if (_syncing) {
      final progress = _progress.trim();
      return _SyncStatus(
        summary: 'Syncing now',
        title: 'Syncing now',
        body: progress.isEmpty ? 'Working through your folders…' : progress,
        icon: Icons.sync_rounded,
        tone: _SyncTone.primary,
      );
    }
    if (!_syncSupported) {
      return const _SyncStatus(
        summary: 'Syncing lives on your other devices',
        title: 'Sync stays with your other devices',
        body:
            'Open NexaDrive on Windows, macOS, Linux or Android to keep folders in step.',
        icon: Icons.desktop_windows_rounded,
        tone: _SyncTone.calm,
      );
    }
    if (_conflicts > 0) {
      final noun = _conflicts == 1 ? 'folder needs' : 'folders need';
      return _SyncStatus(
        summary: '$_conflicts $noun attention',
        title: '$_conflicts $noun attention',
        body: 'Open the files below to choose which versions to keep.',
        icon: Icons.folder_open_outlined,
        tone: _SyncTone.warning,
      );
    }
    if (_folderPath == null) {
      return const _SyncStatus(
        summary: 'Ready to set up',
        title: 'Nothing to sync yet',
        body:
            'Choose a folder and NexaDrive will keep it in step with your cloud.',
        icon: Icons.folder_off_outlined,
        tone: _SyncTone.calm,
      );
    }
    final lastResult = _lastResult;
    if (lastResult != null &&
        (lastResult.error != null || lastResult.errors > 0)) {
      final detail = _lastRunDetail(lastResult);
      return _SyncStatus(
        summary: 'Last run needs a retry',
        title: 'Last run needs a retry',
        body: detail,
        icon: Icons.error_outline_rounded,
        tone: _SyncTone.warning,
      );
    }
    final relative = _relativeTime(_lastSyncAt);
    if (relative == null) {
      return const _SyncStatus(
        summary: 'Ready for the first backup',
        title: 'Everything is ready',
        body: 'Your folder is set. Tap Sync now to make the first backup.',
        icon: Icons.check_circle_outline_rounded,
        tone: _SyncTone.success,
      );
    }
    return _SyncStatus(
      summary: 'Last synced $relative',
      title: 'Everything is synced',
      body: 'This device is up to date. Last synced $relative.',
      icon: Icons.check_circle_outline_rounded,
      tone: _SyncTone.success,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyle.labelMedium.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The one question the screen exists to answer: is my stuff syncing?
class _StatusCard extends StatelessWidget {
  final _SyncStatus status;
  final bool showProgress;

  const _StatusCard({
    required this.status,
    required this.showProgress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final (Color tint, Color container) = switch (status.tone) {
      _SyncTone.primary => (scheme.primary, scheme.primaryContainer),
      _SyncTone.calm => (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest,
        ),
      _SyncTone.warning => (
          AppColors.warningFor(brightness),
          AppColors.warningContainerFor(brightness),
        ),
      _SyncTone.success => (
          AppColors.successFor(brightness),
          AppColors.successContainerFor(brightness),
        ),
    };

    return NexaSurface(
      level: NexaSurfaceLevel.surface,
      padding: const EdgeInsets.all(AppDimens.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: AppDimens.iconTile,
                height: AppDimens.iconTile,
                decoration: BoxDecoration(
                  color: container,
                  borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
                ),
                child: Icon(status.icon, color: tint),
              ),
              const SizedBox(width: AppDimens.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.title,
                      style: AppTextStyle.titleMedium.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppDimens.space4),
                    Text(
                      status.body,
                      style: AppTextStyle.bodyMedium.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: AppDimens.space16),
            LinearProgressIndicator(
              minHeight: AppDimens.space4,
              backgroundColor: scheme.primaryContainer,
              color: scheme.primary,
            ),
          ],
        ],
      ),
    );
  }
}

class _AndroidFoldersCard extends StatelessWidget {
  final List<Map<String, String>> folders;
  final VoidCallback onChoose;
  final ValueChanged<Map<String, String>> onRemove;

  const _AndroidFoldersCard({
    required this.folders,
    required this.onChoose,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NexaSurface(
      level: NexaSurfaceLevel.surface,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (folders.isEmpty)
            Text(
              'No phone folders selected yet',
              style: AppTextStyle.bodyMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (final folder in folders) ...[
              Row(
                children: [
                  NexaFileGlyph.folder(size: AppDimens.iconLarge),
                  const SizedBox(width: AppDimens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder['name'] ?? 'Phone folder',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.titleMedium.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          'Saved to My Files/${folder['remoteName'] ?? folder['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.bodySmall.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove folder',
                    onPressed: () => onRemove(folder),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                ],
              ),
              if (folder != folders.last)
                const Divider(height: AppDimens.space20),
            ],
          const SizedBox(height: AppDimens.space12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onChoose,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add another folder'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final String? folder;
  final VoidCallback onChoose;
  final VoidCallback onClear;

  const _FolderCard({
    required this.folder,
    required this.onChoose,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NexaSurface(
      level: NexaSurfaceLevel.surface,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            folder ?? 'No folder selected',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.titleMedium.copyWith(
              color:
                  folder == null ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
          ),
          const SizedBox(height: AppDimens.space12),
          Wrap(
            spacing: AppDimens.space8,
            runSpacing: AppDimens.space4,
            children: [
              OutlinedButton.icon(
                onPressed: onChoose,
                icon: const Icon(Icons.folder_open_rounded,
                    size: AppDimens.iconSmall),
                label: Text(folder == null ? 'Choose folder' : 'Change folder'),
              ),
              if (folder != null)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.link_off_rounded,
                      size: AppDimens.iconSmall),
                  label: const Text('Stop syncing'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LastRunCard extends StatelessWidget {
  final SyncResult result;
  final VoidCallback onRetry;
  const _LastRunCard({required this.result, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final failed = result.error != null || result.errors > 0;
    final detail = _lastRunDetail(result);
    return NexaSurface(
      level: NexaSurfaceLevel.surface,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failed) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: AppDimens.iconMedium,
                    color: AppColors.warningFor(brightness)),
                const SizedBox(width: AppDimens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last run needs a retry',
                        style: AppTextStyle.titleMedium
                            .copyWith(color: scheme.onSurface),
                      ),
                      const SizedBox(height: AppDimens.space4),
                      Text(
                        detail,
                        style: AppTextStyle.bodySmall.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            NexaTextButton(
              onPressed: onRetry,
              icon:
                  const Icon(Icons.refresh_rounded, size: AppDimens.iconSmall),
              child: const Text('Retry'),
            ),
            const Divider(height: AppDimens.space20),
          ],
          Text(
            'Last run',
            style: AppTextStyle.titleMedium.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: AppDimens.space8),
          _Row(label: 'Uploaded', value: result.uploaded),
          _Row(label: 'Downloaded', value: result.downloaded),
          _Row(label: 'Deleted', value: result.deleted),
          _Row(label: 'Conflicts', value: result.conflicts, warn: true),
          _Row(label: 'Errors', value: result.errors, warn: true),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final int value;
  final bool warn;
  const _Row({required this.label, required this.value, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final warning = warn && value > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyle.bodyMedium.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (warning) ...[
                Icon(
                  Icons.warning_amber_rounded,
                  size: AppDimens.iconSmall,
                  color: AppColors.warningFor(brightness),
                ),
                const SizedBox(width: AppDimens.space4),
              ],
              Text(
                '$value',
                style: AppTextStyle.titleSmall.copyWith(
                  color: warning
                      ? AppColors.warningFor(brightness)
                      : scheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Conflicts with real resolution actions, instead of a number with no path
/// forward.
class _ConflictCard extends StatefulWidget {
  final Api api;
  final VoidCallback onResolved;
  const _ConflictCard({
    super.key,
    required this.api,
    required this.onResolved,
  });

  @override
  State<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends State<_ConflictCard> {
  List<Map<String, String>> _items = const [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final items = await SyncManager(widget.api).conflicts();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = _friendlyError(
            e,
            verb: 'load',
            subject: 'the files that need attention',
          );
        });
      }
    }
  }

  Future<void> _resolve(
    String path,
    Future<void> Function(SyncManager, String) action,
  ) async {
    try {
      await action(SyncManager(widget.api), path);
      if (!mounted) return;
      setState(() => _items.removeWhere((i) => i['path'] == path));
      widget.onResolved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(_friendlyError(e, verb: 'save', subject: 'that choice')),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateKey = _loading
        ? 'loading'
        : _loadError != null
            ? 'error'
            : _items.isEmpty
                ? 'empty'
                : 'content';
    return NexaStateSwitcher(
      stateKey: ValueKey(stateKey),
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final warning = AppColors.warningFor(brightness);

    if (_loading) {
      return NexaSurface(
        level: NexaSurfaceLevel.surface,
        padding: const EdgeInsets.all(AppDimens.space16),
        child: Row(
          children: [
            SizedBox(
              width: AppDimens.iconMedium,
              height: AppDimens.iconMedium,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: AppDimens.space12),
            Expanded(
              child: Text(
                'Checking for files that need a decision…',
                style: AppTextStyle.bodyMedium.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return NexaSurface(
        level: NexaSurfaceLevel.surface,
        padding: const EdgeInsets.all(AppDimens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We couldn’t load these files',
              style: AppTextStyle.titleMedium.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: AppDimens.space4),
            Text(
              '$_loadError Your other sync settings are still here.',
              style: AppTextStyle.bodySmall.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            NexaTextButton(
              onPressed: _load,
              icon:
                  const Icon(Icons.refresh_rounded, size: AppDimens.iconSmall),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return NexaSurface(
        level: NexaSurfaceLevel.surface,
        padding: const EdgeInsets.all(AppDimens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nothing left to decide here',
              style: AppTextStyle.titleMedium.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: AppDimens.space4),
            Text(
              'Those files may have been settled on another device.',
              style: AppTextStyle.bodySmall.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            NexaTextButton(
              onPressed: _load,
              icon:
                  const Icon(Icons.refresh_rounded, size: AppDimens.iconSmall),
              child: const Text('Check again'),
            ),
          ],
        ),
      );
    }

    return NexaSurface(
      level: NexaSurfaceLevel.surface,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_open_outlined,
                  size: AppDimens.iconMedium, color: warning),
              const SizedBox(width: AppDimens.space8),
              Text(
                'Needs your decision',
                style:
                    AppTextStyle.titleMedium.copyWith(color: scheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space4),
          Text(
            'Both versions changed. Keep the one you want.',
            style:
                AppTextStyle.bodySmall.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDimens.space12),
          for (final item in _items) ...[
            _ConflictRow(item: item, onResolve: _resolve),
            if (item != _items.last) const Divider(height: AppDimens.space20),
          ],
        ],
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  final Map<String, String> item;
  final Future<void> Function(
    String path,
    Future<void> Function(SyncManager, String) action,
  ) onResolve;

  const _ConflictRow({
    required this.item,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = item['path'] ?? '';
    final basename = _fileName(path);
    final name = basename.isEmpty ? 'This file' : basename;
    final copyName = _fileName(item['conflictPath'] ?? '');
    final copyLabel = copyName.isEmpty ? 'the cloud copy' : '“$copyName”';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Conflict in $name. Both versions changed. '
              'Keep the one you want.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style:
                    AppTextStyle.titleSmall.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: AppDimens.space2),
              Text(
                path.isEmpty ? 'Location unavailable' : path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.bodySmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.space8),
        Text(
          'Keep mine uploads your copy; keep cloud replaces it here; '
          'keep both also keeps $copyLabel on this device.',
          style:
              AppTextStyle.bodySmall.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppDimens.space8),
        Wrap(
          spacing: AppDimens.space8,
          runSpacing: AppDimens.space4,
          children: [
            FilledButton.tonal(
              onPressed: path.isEmpty
                  ? null
                  : () => onResolve(
                        path,
                        (m, p) => m.resolveConflictKeepLocal(p),
                      ),
              child: const Text('Keep mine'),
            ),
            OutlinedButton(
              onPressed: path.isEmpty
                  ? null
                  : () => onResolve(
                        path,
                        (m, p) => m.resolveConflictKeepRemote(p),
                      ),
              child: const Text('Keep cloud'),
            ),
            TextButton(
              onPressed: path.isEmpty
                  ? null
                  : () => onResolve(
                        path,
                        (m, p) => m.resolveConflictKeepBoth(p),
                      ),
              child: const Text('Keep both'),
            ),
          ],
        ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final Map<String, dynamic> device;
  final bool isThisDevice;
  final VoidCallback onRename;
  final VoidCallback onRevoke;

  const _DeviceRow({
    required this.device,
    required this.isThisDevice,
    required this.onRename,
    required this.onRevoke,
  });

  static (IconData, String) _platformVisual(String? platform) {
    switch (platform) {
      case 'android':
        return (Icons.smartphone_rounded, 'Android');
      case 'windows':
        return (Icons.laptop_windows_rounded, 'Windows');
      case 'linux':
        return (Icons.computer_rounded, 'Linux');
      case 'macos':
        return (Icons.laptop_mac_rounded, 'macOS');
      default:
        return (Icons.devices_rounded, 'Unknown platform');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, platformLabel) =
        _platformVisual(device['platform']?.toString());
    final lastSeen =
        DateTime.tryParse(device['last_seen_at']?.toString() ?? '');
    final name = device['name']?.toString() ?? 'Device';

    return NexaSurface(
      level: NexaSurfaceLevel.surface,
      child: ListTile(
        minTileHeight: AppDimens.listHeight,
        leading: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          foregroundColor: scheme.onSecondaryContainer,
          child: Icon(icon, size: AppDimens.iconMedium),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    AppTextStyle.titleMedium.copyWith(color: scheme.onSurface),
              ),
            ),
            if (isThisDevice) ...[
              const SizedBox(width: AppDimens.space8),
              Badge(
                backgroundColor: scheme.primaryContainer,
                label: Text(
                  'This device',
                  style: AppTextStyle.labelSmall.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Semantics(
          label: 'Platform: $platformLabel',
          child: Text(
            lastSeen == null
                ? platformLabel
                : '$platformLabel · last seen ${Format.relTime(lastSeen)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.bodySmall.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Device options',
          onSelected: (value) {
            if (value == 'rename') onRename();
            if (value == 'unlink') onRevoke();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'unlink', child: Text('Unlink device')),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Notice({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NexaSurface(
      level: NexaSurfaceLevel.surface,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppDimens.iconTile,
            height: AppDimens.iconTile,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
            ),
            child: Icon(
              icon,
              size: AppDimens.iconSmall,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.titleMedium.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                Text(
                  body,
                  style: AppTextStyle.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An inline failure with exactly one way forward. Used when local settings
/// are fine but one supporting list could not be loaded.
class _ActionNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final bool loading;

  const _ActionNotice({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NexaSurface(
      level: NexaSurfaceLevel.surface,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppDimens.iconTile,
            height: AppDimens.iconTile,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
            ),
            child: Icon(
              icon,
              size: AppDimens.iconSmall,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.titleMedium.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                Text(
                  body,
                  style: AppTextStyle.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppDimens.space8),
                if (loading)
                  SizedBox(
                    width: AppDimens.iconSmall,
                    height: AppDimens.iconSmall,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                else
                  NexaTextButton(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh_rounded,
                        size: AppDimens.iconSmall),
                    child: Text(actionLabel),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _SyncTone { primary, calm, warning, success }

/// One resolved description of sync, shared by the page header and its status
/// card so the two can never tell different stories.
class _SyncStatus {
  final String summary;
  final String title;
  final String body;
  final IconData icon;
  final _SyncTone tone;

  const _SyncStatus({
    required this.summary,
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
  });
}

/// Human relative time for the header: "Last synced 4 minutes ago", not "4m".
String? _relativeTime(DateTime? time) {
  if (time == null) return null;
  final difference = DateTime.now().difference(time);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes;
    return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
  }
  if (difference.inHours < 24) {
    final hours = difference.inHours;
    return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  }
  if (difference.inDays == 1) return 'yesterday';
  if (difference.inDays < 7) return '${difference.inDays} days ago';
  return Format.relTime(time);
}

/// Turns "Request failed (500)" and socket noise into a sentence that says
/// what failed and what the person can do next.
String _friendlyError(
  Object error, {
  required String verb,
  required String subject,
}) {
  if (error is ApiException) {
    if (error.status == 401) {
      return 'Your session expired. Sign in again so we can $verb $subject.';
    }
    if (error.status == 403) {
      return 'You don’t have permission to $verb $subject.';
    }
    if (error.status >= 500) {
      return 'The server couldn’t $verb $subject right now. Try again in a moment.';
    }
    final message = error.message.trim();
    final lowered = message.toLowerCase();
    final vague = message.isEmpty ||
        lowered == 'request failed' ||
        lowered.startsWith('request failed (') ||
        lowered == 'unknown error';
    if (!vague) return 'We couldn’t $verb $subject: $message';
  }
  final text = error.toString().toLowerCase();
  if (error is SocketException ||
      text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('clientexception') ||
      text.contains('timeoutexception')) {
    return 'You appear to be offline. We couldn’t $verb $subject.';
  }
  return 'We couldn’t $verb $subject. Try again in a moment.';
}

/// Keeps a failed run's explanation warm and specific, without rewording a
/// message the sync engine already made actionable.
String _lastRunDetail(SyncResult result) {
  final reported = result.error?.trim() ?? '';
  if (reported.isNotEmpty) {
    final lowered = reported.toLowerCase();
    final alreadyFriendly = [
      'we couldn’t',
      'your session expired',
      'you don’t have permission',
      'the server couldn’t',
      'you appear to be offline',
    ].any(lowered.startsWith);
    if (alreadyFriendly) return reported;
    return _friendlyError(
      reported,
      verb: 'finish',
      subject: 'the last sync',
    );
  }
  final noun = result.errors == 1 ? 'file' : 'files';
  return '${result.errors} $noun could not be transferred. Try running sync again.';
}

/// The visible name of a path, without platform-specific separators.
String _fileName(String path) {
  final parts =
      path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? '' : parts.last;
}
