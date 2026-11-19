import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final scheme = Theme.of(context).colorScheme;
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
                  width: AppDimens.iconTileLarge,
                  height: AppDimens.iconTileLarge,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius:
                        BorderRadius.circular(AppDimens.radiusStandard),
                  ),
                  child: Center(
                    child: entry.isFolder
                        ? const NexaFileGlyph.folder(size: 32)
                        : NexaFileGlyph(
                            name: entry.name,
                            type: entry.type,
                            size: 32,
                          ),
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
                        style: AppTextStyle.titleMedium.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppDimens.space2),
                      Text(
                        kind,
                        style: AppTextStyle.labelSmall.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.space8),
                IconButton.filledTonal(
                  tooltip: 'Copy path',
                  onPressed: _copyPath,
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.secondaryContainer,
                    foregroundColor: scheme.onSecondaryContainer,
                  ),
                  icon: const Icon(Icons.content_copy_rounded),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon:
                      Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space12),
            NexaSurface(
              level: NexaSurfaceLevel.grouped,
              radius: AppDimens.radiusCard,
              padding: const EdgeInsets.all(AppDimens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location',
                    style: AppTextStyle.labelMedium.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space8),
                  SelectableText(
                    entry.path,
                    style: AppTextStyle.bodyMedium.copyWith(
                      color: scheme.onSurface,
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppDimens.space4,
            bottom: AppDimens.space8,
          ),
          child: Text(
            header,
            style: AppTextStyle.labelMedium.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        NexaSurface(
          level: NexaSurfaceLevel.grouped,
          radius: AppDimens.radiusCard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space16,
            vertical: AppDimens.space8,
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(color: scheme.outlineVariant),
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: AppDimens.touchTarget * 2,
            child: Text(
              label,
              style: AppTextStyle.labelMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyle.bodyMedium.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
