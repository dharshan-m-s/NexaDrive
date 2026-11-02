import 'package:flutter/material.dart';

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
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final entry = widget.entry;
    final category = entry.category;
    final kind = FileKind.label(category);
    final name = entry.name;
    final path = entry.path;
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
            NexaSheetHeader(
              title: name,
              subtitle: '$kind in ${_parentPath(path)}',
              onClose: () => Navigator.pop(context),
            ),
            const SizedBox(height: AppDimens.space4),
            Text(
              path,
              style: AppTextStyle.caption.copyWith(
                color: AppColors.textSecondaryFor(brightness),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppDimens.space20),
            _Section(
              header: 'Details',
              children: [
                _InfoRow(label: 'Type', value: kind),
                if (entry.size != null && entry.size! > 0)
                  _InfoRow(label: 'Size', value: Format.bytes(entry.size!))
                else if (isFolder)
                  _InfoRow(label: 'Size', value: 'Unknown (folder)')
                else
                  _InfoRow(label: 'Size', value: '--'),
                if (entry.modified != null)
                  _InfoRow(
                    label: 'Modified',
                    value: Format.shortDateTime(entry.modified!.toLocal()),
                  )
                else
                  _InfoRow(label: 'Modified', value: 'Unknown'),
                if (entry.offlineAvailable == true)
                  const _InfoRow(
                    label: 'Offline',
                    value: 'Available on this device',
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.space16),
            _Section(
              header: 'Actions',
              children: [
                NexaSheetAction(
                  icon: Icons.share_outlined,
                  title: 'Share',
                  subtitle: isFolder
                      ? 'Share this folder with another account'
                      : 'Share this file or create a link',
                  onTap: () => Navigator.pop(context),
                ),
                NexaSheetAction(
                  icon: Icons.download_outlined,
                  title: isFolder ? 'Download folder' : 'Download',
                  subtitle: isFolder
                      ? 'Save this folder to your device'
                      : 'Save this file to your device',
                  onTap: () => Navigator.pop(context),
                ),
                if (isFolder)
                  NexaSheetAction(
                    icon: Icons.folder_open_rounded,
                    title: 'Open folder',
                    subtitle: 'Browse this folder',
                    onTap: () => Navigator.pop(context),
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.space16),
          ],
        ),
      ),
    );
  }

  String _parentPath(String path) {
    final parts = path.split('/');
    if (parts.length <= 1) return 'My files';
    parts.removeLast();
    return parts.join('/');
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
            left: AppDimens.pageMargin,
            bottom: AppDimens.space4,
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
        ...children,
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
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space4),
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
