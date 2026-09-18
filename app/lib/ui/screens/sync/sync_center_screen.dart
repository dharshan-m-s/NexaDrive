import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/sync_service.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_surface.dart';

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
  DateTime? _lastSyncAt;
  String? _thisDeviceId;
  List<Map<String, dynamic>> _devices = [];
  int _conflicts = 0;
  SyncResult? _lastResult;
  bool _syncing = false;
  String _progress = '';

  bool get _syncSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

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
    try {
      final folder = await manager.folder();
      final lastSync = await manager.lastSyncAt();
      final deviceId = await manager.deviceId();
      final conflicts = await manager.conflictCount();
      final devices = await widget.api.syncDevices();
      if (!mounted) return;
      setState(() {
        _folderPath = folder;
        _lastSyncAt = lastSync;
        _thisDeviceId = deviceId;
        _conflicts = conflicts;
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      // Local state still renders even when the device list cannot be fetched,
      // so a network blip never blanks the whole screen.
      final folder = await manager.folder();
      final lastSync = await manager.lastSyncAt();
      final deviceId = await manager.deviceId();
      if (!mounted) return;
      setState(() {
        _folderPath = folder;
        _lastSyncAt = lastSync;
        _thisDeviceId = deviceId;
        _loading = false;
        _loadError = e is ApiException
            ? e.message
            : 'The linked device list could not be loaded.';
      });
    }
  }

  Future<void> _chooseFolder() async {
    final path = await SyncManager(widget.api).pickAndSetFolder();
    if (path == null) return;
    setState(() => _folderPath = path);
  }

  Future<void> _runSync() async {
    setState(() {
      _syncing = true;
      _progress = 'Starting…';
    });
    final manager = SyncManager(widget.api);
    final result = await manager.sync(onProgress: (p) {
      if (mounted) setState(() => _progress = p);
    });
    final conflicts = await manager.conflictCount();
    final lastSync = await manager.lastSyncAt();
    final deviceId = await manager.deviceId();
    List<Map<String, dynamic>> devices = _devices;
    try {
      devices = await widget.api.syncDevices();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _lastResult = result;
      _conflicts = conflicts;
      _lastSyncAt = lastSync;
      _thisDeviceId = deviceId;
      _devices = devices;
      _syncing = false;
      _progress = '';
    });
    if (result.error != null) {
      _toast(result.error!);
    } else if (result.uploaded +
            result.downloaded +
            result.deleted +
            result.conflicts +
            result.errors >
        0) {
      _toast(
        'Sync finished: ${result.uploaded} up, ${result.downloaded} down, '
        '${result.deleted} deleted, ${result.conflicts} conflict(s), '
        '${result.errors} error(s)',
      );
    } else {
      _toast('Everything is up to date');
    }
  }

  Future<void> _clearFolder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop syncing this folder?'),
        content: const Text(
          'Files already synchronized stay where they are. NexaDrive simply '
          'stops watching this folder for changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop syncing'),
          ),
        ],
      ),
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
      builder: (context) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration: const InputDecoration(labelText: 'Device name'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
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
      builder: (context) => AlertDialog(
        title: const Text('Unlink device'),
        content: Text(
          isThisDevice
              ? 'This is the device you are using. Unlinking it stops sync here '
                  'until the next run re-registers it. Continue?'
              : '“${device['name']}” will stop syncing until it links again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unlink'),
          ),
        ],
      ),
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
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync center'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _init,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _init,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.pageMargin,
                  AppDimens.space8,
                  AppDimens.pageMargin,
                  AppDimens.space32,
                ),
                children: [
                  _StatusCard(
                    enabled: _syncing,
                    hasFolder: _folderPath != null,
                    supported: _syncSupported,
                    lastSyncAt: _lastSyncAt,
                    currentActivity: _syncing ? _progress : null,
                    conflicts: _conflicts,
                  ),
                  if (!_syncSupported) ...[
                    const SizedBox(height: AppDimens.space16),
                    const _Notice(
                      icon: Icons.info_outline_rounded,
                      title: 'Folder sync runs on desktop',
                      body:
                          'Windows, Linux and macOS keep a local folder in step '
                          'with your cloud. On Android, uploads are queued and '
                          'resumed instead.',
                    ),
                  ],
                  const SizedBox(height: AppDimens.space24),
                  const _SectionLabel('SYNCED FOLDER'),
                  const SizedBox(height: AppDimens.space8),
                  _FolderCard(
                    folder: _folderPath,
                    onChoose: _chooseFolder,
                    onClear: _clearFolder,
                  ),
                  const SizedBox(height: AppDimens.space24),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed:
                          _syncing || _folderPath == null || !_syncSupported
                              ? null
                              : _runSync,
                      icon: _syncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                  const _SectionLabel('LINKED DEVICES'),
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    'Devices that have synced with this account.',
                    style: AppTextStyle.caption.copyWith(
                      color: AppColors.textSecondaryFor(
                        Theme.of(context).brightness,
                      ),
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
                    const OneUiEmptyState(
                      icon: Icons.devices_other_rounded,
                      title: 'No linked devices yet',
                      hint: 'Run a sync from a computer and it will appear here.',
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
            ),
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
      style: AppTextStyle.listHeader.copyWith(
        color: AppColors.textTertiaryFor(Theme.of(context).brightness),
        letterSpacing: 0.6,
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
    final brightness = Theme.of(context).brightness;
    final (Color tint, IconData icon, String title, String body) = switch ((
      enabled,
      !supported,
      hasFolder,
      conflicts > 0,
    )) {
      (true, _, _, _) => (
          AppColors.accentFor(brightness),
          Icons.sync_rounded,
          'Syncing now',
          currentActivity?.isNotEmpty == true ? currentActivity! : 'Working…',
        ),
      (_, true, _, _) => (
          AppColors.infoFor(brightness),
          Icons.desktop_windows_rounded,
          'Desktop feature',
          'Folder sync is off on this platform.',
        ),
      (_, _, false, _) => (
          AppColors.warningFor(brightness),
          Icons.folder_off_outlined,
          'Sync is off',
          'Choose a folder to keep in step with your cloud.',
        ),
      (_, _, _, true) => (
          AppColors.warningFor(brightness),
          Icons.warning_amber_rounded,
          '$conflicts conflict${conflicts == 1 ? '' : 's'} to resolve',
          'Both copies changed. Pick which version to keep.',
        ),
      _ => (
          AppColors.successFor(brightness),
          Icons.check_circle_outline_rounded,
          'Up to date',
          lastSyncAt == null
              ? 'Not synced yet.'
              : 'Last sync ${Format.relTime(lastSyncAt)}.',
        ),
    };

    return OneUiSurface(
      level: OneUiSurfaceLevel.surface,
      radius: AppDimens.radiusCard,
      padding: const EdgeInsets.all(AppDimens.space20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppDimens.radiusInner),
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
                  style: AppTextStyle.sectionHeader.copyWith(
                    color: AppColors.textPrimaryFor(brightness),
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                Text(
                  body,
                  style: AppTextStyle.rowSubtitle.copyWith(
                    color: AppColors.textSecondaryFor(brightness),
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
    final brightness = Theme.of(context).brightness;
    return OneUiSurface(
      level: OneUiSurfaceLevel.surface,
      radius: AppDimens.radiusCard,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            folder ?? 'No folder selected',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.rowTitle.copyWith(
              color: folder == null
                  ? AppColors.textSecondaryFor(brightness)
                  : AppColors.textPrimaryFor(brightness),
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
    final brightness = Theme.of(context).brightness;
    return OneUiSurface(
      level: OneUiSurfaceLevel.surface,
      radius: AppDimens.radiusCard,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last run',
            style: AppTextStyle.sectionHeader.copyWith(
              color: AppColors.textPrimaryFor(brightness),
            ),
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
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyle.rowSubtitle
                .copyWith(color: AppColors.textSecondaryFor(brightness)),
          ),
          Text(
            '$value',
            style: AppTextStyle.rowTitle.copyWith(
              fontWeight: FontWeight.w700,
              color: warn && value > 0
                  ? AppColors.warningFor(brightness)
                  : AppColors.textPrimaryFor(brightness),
            ),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (_loading || _items.isEmpty) return const SizedBox.shrink();
    return OneUiSurface(
      level: OneUiSurfaceLevel.surface,
      radius: AppDimens.radiusCard,
      color: AppColors.warningContainerFor(brightness),
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conflicts',
            style: AppTextStyle.sectionHeader.copyWith(
              color: AppColors.textPrimaryFor(brightness),
            ),
          ),
          const SizedBox(height: AppDimens.space4),
          Text(
            'A copy of the cloud version was saved next to the local file.',
            style: AppTextStyle.caption
                .copyWith(color: AppColors.textSecondaryFor(brightness)),
          ),
          const SizedBox(height: AppDimens.space12),
          for (final item in _items) ...[
            Text(
              item['path'] ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.rowSubtitle.copyWith(
                color: AppColors.textPrimaryFor(brightness),
                fontWeight: FontWeight.w600,
              ),
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
    final brightness = Theme.of(context).brightness;
    final (icon, platformLabel) = _platformVisual(device['platform']?.toString());
    final lastSeen = DateTime.tryParse(device['last_seen_at']?.toString() ?? '');
    final name = device['name']?.toString() ?? 'Device';

    return OneUiSurface(
      level: OneUiSurfaceLevel.surface,
      radius: AppDimens.radiusTile,
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space16,
        AppDimens.space12,
        AppDimens.space8,
        AppDimens.space12,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentSubtleFor(brightness),
              borderRadius: BorderRadius.circular(AppDimens.radiusInner),
            ),
            child: Icon(icon, color: AppColors.accentTextFor(brightness)),
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
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.rowTitle.copyWith(
                          color: AppColors.textPrimaryFor(brightness),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isThisDevice) ...[
                      const SizedBox(width: AppDimens.space8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.space8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentContainerFor(brightness),
                          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                        ),
                        child: Text(
                          'This device',
                          style: AppTextStyle.micro.copyWith(
                            color: AppColors.onAccentContainerFor(brightness),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppDimens.space2),
                Semantics(
                  label: 'Platform: $platformLabel',
                  child: Text(
                    lastSeen == null
                        ? platformLabel
                        : '$platformLabel · last seen ${Format.relTime(lastSeen)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption.copyWith(
                      color: AppColors.textSecondaryFor(brightness),
                    ),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
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
        ],
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
    final brightness = Theme.of(context).brightness;
    return OneUiSurface(
      level: OneUiSurfaceLevel.surface,
      radius: AppDimens.radiusCard,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppDimens.iconSmall,
              color: AppColors.textSecondaryFor(brightness)),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.rowTitle.copyWith(
                    color: AppColors.textPrimaryFor(brightness),
                  ),
                ),
                const SizedBox(height: AppDimens.space4),
                Text(
                  body,
                  style: AppTextStyle.caption
                      .copyWith(color: AppColors.textSecondaryFor(brightness)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
