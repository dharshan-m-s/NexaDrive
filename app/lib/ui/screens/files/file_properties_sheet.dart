import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/file_kind.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/nexa_components.dart';

class FilePropertiesSheet extends StatefulWidget {
  final FileEntry entry;
  final Api api;
  const FilePropertiesSheet({
    super.key,
    required this.entry,
    required this.api,
  });

  @override
  State<FilePropertiesSheet> createState() => _FilePropertiesSheetState();
}

class _FilePropertiesSheetState extends State<FilePropertiesSheet> {
  Future<void> _copyPath() async {
    await Clipboard.setData(ClipboardData(text: widget.entry.path));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Path copied')));
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final entry = widget.entry;
    final category = entry.category;
    final kind = FileKind.label(category);
    final isFolder = category == Category.folder;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageMargin,
          AppDimens.space16,
          AppDimens.pageMargin,
          AppDimens.space16,
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
                    size: AppDimens.iconLarge,
                  ),
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.rowTitle.copyWith(
                          color: AppColors.textPrimaryFor(brightness),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppDimens.space2),
                      Text(
                        kind,
                        style: AppTextStyle.caption.copyWith(
                          color: AppColors.textSecondaryFor(brightness),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.space8),
                NexaLiquidGlass(
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  padding: EdgeInsets.zero,
                  blurSigma: 10,
                  showShadow: false,
                  child: IconButton(
                    tooltip: 'Copy path',
                    onPressed: _copyPath,
                    icon: const Icon(Icons.content_copy_rounded),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space12),
            NexaSurface(
              level: NexaSurfaceLevel.grouped,
              radius: AppDimens.radiusMedium,
              padding: const EdgeInsets.all(AppDimens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LOCATION',
                    style: AppTextStyle.caption.copyWith(
                      color: AppColors.textSecondaryFor(brightness),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space8),
                  SelectableText(
                    entry.path,
                    style: AppTextStyle.rowTitle.copyWith(
                      color: AppColors.textPrimaryFor(brightness),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.space20),
            _Section(
              header: 'Details',
              children: [
                _InfoRow(label: 'Type', value: kind),
                if (!isFolder && entry.size != null)
                  _InfoRow(label: 'Size', value: Format.bytes(entry.size!)),
                if (entry.modified != null)
                  _InfoRow(
                    label: 'Modified',
                    value: Format.shortDateTime(entry.modified!.toLocal()),
                  ),
                if (entry.offlineAvailable == true)
                  const _InfoRow(
                    label: 'Offline',
                    value: 'Available on this device',
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.space16),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String header;
  final List<Widget> children;
  const _Section({required this.header, required this.children});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppDimens.space4,
            bottom: AppDimens.space8,
          ),
          child: Text(
            header.toUpperCase(),
            style: AppTextStyle.caption.copyWith(
              color: AppColors.textSecondaryFor(brightness),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
        NexaSurface(
          level: NexaSurfaceLevel.grouped,
          radius: AppDimens.radiusMedium,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space16,
            vertical: AppDimens.space8,
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: AppDimens.space12,
                    thickness: 0.5,
                    color: AppColors.separatorFor(brightness),
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final secondary = AppColors.textSecondaryFor(brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: AppTextStyle.caption.copyWith(color: secondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyle.rowTitle.copyWith(
                color: AppColors.textPrimaryFor(brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
