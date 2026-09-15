import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../../services/sync_service.dart';
import '../../widgets/one_ui_surface.dart';

class SyncCenterScreen extends StatefulWidget {
  final Api api;
  const SyncCenterScreen({super.key, required this.api});

  @override
  State<SyncCenterScreen> createState() => _SyncCenterScreenState();
}

class _SyncCenterScreenState extends State<SyncCenterScreen> {
  bool _loading = true;
  String? _folderPath;
  List<Map<String, dynamic>> _devices = [];
  int _conflicts = 0;
  SyncResult? _lastResult;
  bool _syncing = false;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final manager = SyncManager(widget.api);
      final folder = await manager.folder();
      final devices = await widget.api.syncDevices();
      final conflicts = await manager.conflictCount();
      if (!mounted) return;
      setState(() {
        _folderPath = folder;
        _devices = devices;
        _conflicts = conflicts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _chooseFolder() async {
    final manager = SyncManager(widget.api);
    final path = await manager.pickAndSetFolder();
    if (path == null) return;
    setState(() => _folderPath = path);
  }

  Future<void> _runSync() async {
    setState(() {
      _syncing = true;
      _progress = '';
    });
    final result = await SyncManager(widget.api).sync(onProgress: (p) {
      if (mounted) setState(() => _progress = p);
    });
    final conflicts = await SyncManager(widget.api).conflictCount();
    if (!mounted) return;
    setState(() {
      _lastResult = result;
      _conflicts = conflicts;
      _syncing = false;
    });
    if (result.uploaded + result.downloaded + result.deleted + result.errors > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync done: ${result.uploaded} up, ${result.downloaded} down, '
            '${result.deleted} deleted, ${result.errors} error(s)',
          ),
        ),
      );
    }
  }

  Future<void> _clearFolder() async {
    await SyncManager(widget.api).clearFolder();
    setState(() => _folderPath = null);
  }

  Future<void> _revokeDevice(String id) async {
    try {
      await widget.api.revokeSyncDevice(id);
      setState(() => _devices.removeWhere((d) => d['id'] == id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(title: const Text('Sync center')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageMargin,
                AppDimens.space8,
                AppDimens.pageMargin,
                AppDimens.space24,
              ),
              children: [
                // Selected folder
                OneUiSurface(
                  level: OneUiSurfaceLevel.surface,
                  padding: const EdgeInsets.all(AppDimens.space16),
                  radius: AppDimens.radiusCard,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selected folder',
                        style: AppTextStyle.sectionHeader.copyWith(
                          color: AppColors.textPrimaryFor(brightness),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppDimens.space6),
                      Text(
                        _folderPath ?? 'No folder selected',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.caption
                            .copyWith(color: AppColors.textSecondaryFor(brightness)),
                      ),
                      const SizedBox(height: AppDimens.space12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _chooseFolder,
                            icon: const Icon(Icons.folder_open_rounded, size: AppDimens.iconSmall),
                            label: const Text('Choose'),
                          ),
                          if (_folderPath != null) ...[
                            const SizedBox(width: AppDimens.space8),
                            OutlinedButton.icon(
                              onPressed: _clearFolder,
                              icon: const Icon(Icons.link_off_rounded, size: AppDimens.iconSmall),
                              label: const Text('Unlink'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimens.space16),

                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _syncing ? null : _runSync,
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
                if (_progress.isNotEmpty) ...[
                  const SizedBox(height: AppDimens.space8),
                  Text(
                    _progress,
                    style: AppTextStyle.caption
                        .copyWith(color: AppColors.textSecondaryFor(brightness)),
                  ),
                ],

                if (_lastResult != null) ...[
                  const SizedBox(height: AppDimens.space16),
                  OneUiSurface(
                    level: OneUiSurfaceLevel.surface,
                    padding: const EdgeInsets.all(AppDimens.space16),
                    radius: AppDimens.radiusCard,
                    child: Column(
                      children: [
                        _statRow(context, 'Uploaded', _lastResult!.uploaded),
                        _statRow(context, 'Downloaded', _lastResult!.downloaded),
                        _statRow(context, 'Deleted', _lastResult!.deleted),
                        _statRow(context, 'Conflicts', _lastResult!.conflicts,
                            error: _lastResult!.conflicts > 0),
                        _statRow(context, 'Errors', _lastResult!.errors,
                            error: _lastResult!.errors > 0),
                      ],
                    ),
                  ),
                ],

                if (_conflicts > 0) ...[
                  const SizedBox(height: AppDimens.space16),
                  OneUiSurface(
                    level: OneUiSurfaceLevel.surface,
                    radius: AppDimens.radiusCard,
                    color: AppColors.warningFor(brightness).withValues(alpha: 0.14),
                    padding: const EdgeInsets.all(AppDimens.space16),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: AppColors.warningFor(brightness)),
                        const SizedBox(width: AppDimens.space12),
                        Expanded(
                          child: Text(
                            '${Format.count(_conflicts, 'conflicted file')} to resolve',
                            style: AppTextStyle.rowTitle.copyWith(
                              color: AppColors.textPrimaryFor(brightness),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppDimens.space24),
                Text(
                  'LINKED DEVICES'.toUpperCase(),
                  style: AppTextStyle.listHeader.copyWith(
                    color: AppColors.textTertiaryFor(brightness),
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: AppDimens.space8),
                if (_devices.isEmpty)
                  Text(
                    'No devices linked yet. Run sync from another device to link it.',
                    style: AppTextStyle.caption
                        .copyWith(color: AppColors.textSecondaryFor(brightness)),
                  )
                else
                  for (final d in _devices)
                    OneUiSurface(
                      level: OneUiSurfaceLevel.surface,
                      margin: const EdgeInsets.only(bottom: AppDimens.space8),
                      radius: AppDimens.radiusTile,
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDimens.radiusTile),
                        ),
                        leading: const Icon(Icons.devices_rounded),
                        title: Text(
                          d['name']?.toString() ?? 'Device',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          'Last seen ${Format.relTime(DateTime.tryParse(d['last_seen_at']?.toString() ?? ''))}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: IconButton(
                          tooltip: 'Revoke device',
                          icon: Icon(
                            Icons.link_off_rounded,
                            color: AppColors.errorFor(brightness),
                          ),
                          onPressed: () => _revokeDevice(d['id'] as String),
                        ),
                        ),
                      ),
                    ),
              ],
            ),
    );
  }

  Widget _statRow(BuildContext context, String label, int value,
      {bool error = false}) {
    final secondary =
        AppColors.textSecondaryFor(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyle.rowSubtitle.copyWith(color: secondary)),
          Text(
            '$value',
            style: AppTextStyle.rowTitle.copyWith(
              fontWeight: FontWeight.w700,
              color: error
                  ? AppColors.errorFor(Theme.of(context).brightness)
                  : AppColors.textPrimaryFor(Theme.of(context).brightness),
            ),
          ),
        ],
      ),
    );
  }
}