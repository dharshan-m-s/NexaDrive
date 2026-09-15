import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/file_kind.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';

/// One UI details sheet — path, kind, size and modified time in a calm,
/// low-contrast layout.
class FileDetailsSheet extends StatelessWidget {
  final FileEntry file;
  final Api api;
  const FileDetailsSheet({super.key, required this.file, required this.api});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final category = file.category;

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
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: FileKind.tileFill(category, brightness),
                    borderRadius: BorderRadius.circular(AppDimens.radiusInner),
                  ),
                  child: Icon(
                    FileKind.icon(category),
                    color: FileKind.tint(category, brightness),
                    size: 26,
                  ),
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.rowTitle.copyWith(
                          color: AppColors.textPrimaryFor(brightness),
                        ),
                      ),
                      const SizedBox(height: AppDimens.space2),
                      Text(
                        FileKind.label(category),
                        style: AppTextStyle.caption
                            .copyWith(color: AppColors.textSecondaryFor(brightness)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space20),
            _InfoRow(label: 'Location', value: file.path),
            if (file.size != null) _InfoRow(label: 'Size', value: Format.bytes(file.size!)),
            if (file.modified != null)
              _InfoRow(
                label: 'Modified',
                value: Format.shortDateTime(file.modified!.toLocal()),
              ),
            if (file.offlineAvailable == true)
              const _InfoRow(
                label: 'Offline',
                value: 'Available on this device',
              ),
            const SizedBox(height: AppDimens.space20),
          ],
        ),
      ),
    );
  }
}

/// Label/value pair used in the details sheet.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondaryFor(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: AppTextStyle.caption.copyWith(color: secondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyle.rowTitle.copyWith(
                color: AppColors.textPrimaryFor(Theme.of(context).brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }
}