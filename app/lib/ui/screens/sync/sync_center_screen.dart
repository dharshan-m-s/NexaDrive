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
  String? _loadError;
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

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _loadError = null;
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

    String? loadError;
    if (localError != null) {
      loadError = 'Local sync settings could not be loaded.';
    } else if (deviceError != null) {
      loadError = deviceError is ApiException
          ? deviceError.message
          : 'The linked device list could not be loaded.';
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
      _loadError = loadError;
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
      if (mounted) _toast(error.toString());
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
      if (mounted) _toast(error.toString());
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
      result = SyncResult(errors: 1, error: error.toString());
    }

    var conflicts = _conflicts;
    DateTime? lastSync = _lastSyncAt;
    var deviceId = _thisDeviceId;
    var folders = _androidFolders;
    var folderLabel = _folderPath;
    List<Map<String, dynamic>> devices = _devices;
    try {
      conflicts = await manager.conflictCount();
      lastSync = await manager.lastSyncAt();
      deviceId = await manager.deviceId();
      if (Platform.isAndroid) {
        folders = await manager.androidFolders();
        folderLabel = await manager.folder();
      }
      devices = await widget.api.syncDevices();
    } catch (_) {
      // The upload result is still authoritative even if refreshing metadata
      // or the linked-device list fails.
    }
    if (!mounted) return;
    setState(() {
      _lastResult = result;
      _conflicts = conflicts;
      _lastSyncAt = lastSync;
      _thisDeviceId = deviceId;
      _devices = devices;
      _androidFolders = folders;
      _folderPath = folderLabel;
      _syncing = false;
      _progress = '';
    });
    if (result.error != null) {
      _toast(result.error!);
    } else if (result.uploaded > 0 || result.errors > 0) {
      _toast(
          'Backup finished: ${result.uploaded} uploaded, ${result.errors} error(s)');
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
      if (mounted) _toast(e.toString());
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
      if (mounted) _toast(e.toString());
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
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NexaPage(
          title: 'Sync center',
          subtitle: _loading ? null : _summary,
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
            stateKey: ValueKey(_loading ? 'loading' : 'content'),
            child: _loading
                ? const NexaLoadingBlock()
                : RefreshIndicator(
                    onRefresh: _init,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: AppDimens.space8),
                      children: [
                        _StatusCard(
                          enabled: _syncing,
                          hasFolder: _folderPath != null,
                          supported: _syncSupported,
                          lastSyncAt: _lastSyncAt,
                          currentActivity: _syncing ? _progress : null,
                          conflicts: _conflicts,
                        ),
                        if (Platform.isAndroid) ...[
                          const SizedBox(height: AppDimens.space16),
                          const _Notice(
                            icon: Icons.info_outline_rounded,
                            title: 'One-way phone folder backup',
                            body:
                                'Add multiple phone folders. Sync now uploads every file '
                                'and subfolder from each one, then uploads new or changed '
                                'files on later runs. Phone files are never deleted.',
                          ),
                        ],
                        const SizedBox(height: AppDimens.space24),
                        _SectionLabel(Platform.isAndroid
                            ? 'Phone folders'
                            : 'Synced folder'),
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
                            onPressed: _syncing ||
                                    _folderPath == null ||
                                    !_syncSupported
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
                          _LastRunCard(result: _lastResult!),
                        ],
                        if (_conflicts > 0) ...[
                          const SizedBox(height: AppDimens.space16),
                          _ConflictCard(api: widget.api, onResolved: _init),
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
                        if (_loadError != null)
                          _Notice(
                            icon: Icons.cloud_off_rounded,
                            title: 'Device list unavailable',
                            body: _loadError!,
                          )
                        else if (_devices.isEmpty)
                          const NexaEmptyState(
                            icon: Icons.devices_other_rounded,
                            title: 'No linked devices yet',
                            hint:
                                'Run a sync from a computer and it will appear here.',
                          )
                        else
                          for (final device in _devices)
                            Padding(
                              padding: const EdgeInsets.only(
                                  bottom: AppDimens.space8),
                              child: _DeviceRow(
                                device: device,
                                isThisDevice: device['id'] == _thisDeviceId,
                                onRename: () => _renameDevice(device),
                                onRevoke: () => _revokeDevice(device),
                              ),
                            ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// One-line description of the sync state, so the header says more than
  /// the page name.
  String get _summary {
    if (_syncing) return 'Syncing…';
    if (_conflicts > 0) {
      return '$_conflicts conflict${_conflicts == 1 ? '' : 's'}';
    }
    if (_lastSyncAt == null) return 'Never synced';
    return 'Last synced ${Format.relTime(_lastSyncAt)}';
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
  final bool enabled;
  final bool hasFolder;
  final bool supported;
  final DateTime? lastSyncAt;
  final String? currentActivity;
  final int conflicts;

  const _StatusCard({
    required this.enabled,
    required this.hasFolder,
    required this.supported,
    required this.lastSyncAt,
    required this.currentActivity,
    required this.conflicts,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final (
      Color tint,
      Color container,
      IconData icon,
      String title,
      String body
    ) = switch ((
      enabled,
      !supported,
      hasFolder,
      conflicts > 0,
    )) {
      (true, _, _, _) => (
          scheme.primary,
          scheme.primaryContainer,
          Icons.sync_rounded,
          'Syncing now',
          currentActivity?.isNotEmpty == true ? currentActivity! : 'Working…',
        ),
      (_, true, _, _) => (
          scheme.primary,
          scheme.secondaryContainer,
          Icons.desktop_windows_rounded,
          'Desktop feature',
          'Folder sync is off on this platform.',
        ),
      (_, _, false, _) => (
          AppColors.warningFor(brightness),
          AppColors.warningContainerFor(brightness),
          Icons.folder_off_outlined,
          'Sync is off',
          'Choose a folder to keep in step with your cloud.',
        ),
      (_, _, _, true) => (
          AppColors.warningFor(brightness),
          AppColors.warningContainerFor(brightness),
          Icons.warning_amber_rounded,
          '$conflicts conflict${conflicts == 1 ? '' : 's'} to resolve',
          'Both copies changed. Pick which version to keep.',
        ),
      _ => (
          AppColors.successFor(brightness),
          AppColors.successContainerFor(brightness),
          Icons.check_circle_outline_rounded,
          'Up to date',
          lastSyncAt == null
              ? 'Not synced yet.'
              : 'Last sync ${Format.relTime(lastSyncAt)}.',
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
                child: Icon(icon, color: tint),
              ),
              const SizedBox(width: AppDimens.space16),
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
                      style: AppTextStyle.bodyMedium.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (enabled) ...[
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
  const _LastRunCard({required this.result});

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
  const _ConflictCard({required this.api, required this.onResolved});

  @override
  State<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends State<_ConflictCard> {
  List<Map<String, String>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await SyncManager(widget.api).conflicts();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
          content: Text(e.toString()),
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
    final brightness = Theme.of(context).brightness;
    final onContainer = AppColors.onWarningContainerFor(brightness);
    if (_loading || _items.isEmpty) return const SizedBox.shrink();
    return NexaSurface(
      level: NexaSurfaceLevel.surface,
      color: AppColors.warningContainerFor(brightness),
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: AppDimens.iconMedium, color: onContainer),
              const SizedBox(width: AppDimens.space8),
              Text(
                'Conflicts',
                style: AppTextStyle.titleMedium.copyWith(color: onContainer),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space4),
          Text(
            'A copy of the cloud version was saved next to the local file.',
            style: AppTextStyle.bodySmall.copyWith(color: onContainer),
          ),
          const SizedBox(height: AppDimens.space12),
          for (final item in _items) ...[
            Text(
              item['path'] ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.bodyMedium.copyWith(color: onContainer),
            ),
            const SizedBox(height: AppDimens.space8),
            Wrap(
              spacing: AppDimens.space8,
              runSpacing: AppDimens.space4,
              children: [
                FilledButton.tonal(
                  onPressed: () => _resolve(
                    item['path']!,
                    (m, p) => m.resolveConflictKeepLocal(p),
                  ),
                  child: const Text('Keep mine'),
                ),
                OutlinedButton(
                  onPressed: () => _resolve(
                    item['path']!,
                    (m, p) => m.resolveConflictKeepRemote(p),
                  ),
                  child: const Text('Keep cloud'),
                ),
                TextButton(
                  onPressed: () => _resolve(
                    item['path']!,
                    (m, p) => m.resolveConflictKeepBoth(p),
                  ),
                  child: const Text('Keep both'),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space16),
          ],
        ],
      ),
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
