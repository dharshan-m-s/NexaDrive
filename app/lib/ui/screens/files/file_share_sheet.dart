import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../services/api.dart';

/// One UI "Share" sheet — create a share link for one or more files.
class FileShareSheet extends StatefulWidget {
  final Api api;
  final List<FileEntry> files;
  const FileShareSheet({super.key, required this.api, required this.files});

  @override
  State<FileShareSheet> createState() => _FileShareSheetState();
}

class _FileShareSheetState extends State<FileShareSheet> {
  String _permission = 'view';
  bool _busy = false;
  String? _createdUrl;
  String? _createdId;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.createShare(
        path: widget.files.first.path,
        permission: _permission == 'view' ? 'read' : 'write',
      );
      final token = result['token']?.toString();
      final id = result['id']?.toString();
      if (!mounted) return;
      setState(() {
        _createdUrl = token == null || token.isEmpty
            ? ''
            : '${widget.api.session.serverUrl}/api/share/$token/download';
        _createdId = id;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _remove() async {
    if (_createdId == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    try {
      await widget.api.deleteShare(_createdId!);
      if (mounted) Navigator.of(context).pop();
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
    final accent = AppColors.accentFor(brightness);
    final secondary = AppColors.textSecondaryFor(brightness);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageMargin, AppDimens.space16, AppDimens.pageMargin, AppDimens.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.share_outlined, color: accent),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Text(
                    widget.files.length == 1
                        ? 'Share "${widget.files.first.name}"'
                        : 'Share ${widget.files.length} items',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.rowTitle.copyWith(
                      color: AppColors.textPrimaryFor(brightness),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space16),

            if (_createdUrl != null) ...[
              Text(
                'Anyone with the link can view this file.',
                style: AppTextStyle.caption.copyWith(color: secondary),
              ),
              const SizedBox(height: AppDimens.space12),
              Container(
                padding: const EdgeInsets.all(AppDimens.space12),
                decoration: BoxDecoration(
                  color: brightness == Brightness.dark
                      ? AppColors.surfaceAltDark
                      : AppColors.surfaceAltLight,
                  borderRadius: BorderRadius.circular(AppDimens.radiusInner),
                ),
                child: SelectionArea(
                  child: Text(
                    _createdUrl!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption.copyWith(
                      color: AppColors.textPrimaryFor(brightness),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.space12),
            ] else ...[
              const Text('Share via link'),
              const SizedBox(height: AppDimens.space8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'view',
                    label: Text('View only'),
                    icon: Icon(Icons.visibility_outlined),
                  ),
                  ButtonSegment(
                    value: 'download',
                    label: Text('Download'),
                    icon: Icon(Icons.download_outlined),
                  ),
                ],
                selected: {_permission},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _permission = s.first),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppDimens.space12),
                Text(
                  _error!,
                  style: AppTextStyle.caption.copyWith(
                    color: brightness == Brightness.dark
                        ? AppColors.errorDark
                        : AppColors.errorLight,
                  ),
                ),
              ],
              const SizedBox(height: AppDimens.space16),
            ],

            Row(
              children: [
                if (_createdUrl != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _remove,
                      icon: const Icon(Icons.link_off_rounded,
                          size: AppDimens.iconSmall),
                      label: const Text('Remove link'),
                    ),
                  )
                else
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _create,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.add_link_rounded,
                              size: AppDimens.iconSmall),
                      label: const Text('Create link'),
                    ),
                  ),
                const SizedBox(width: AppDimens.space12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}