import 'package:flutter/material.dart';

import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import 'nexa_avatar.dart';
import 'nexa_file_glyph.dart';

/// Shared-file row used by the Shared tab and the dashboard.
///
/// The file itself is the primary artwork; a small collaborator avatar sits on
/// the edge so ownership is personal without competing with the filename.
class NexaSharedTile extends StatelessWidget {
  final String name;
  final String path;
  final bool isFolder;
  final String? person;
  final String subtitle;
  final Widget? trailing;
  final bool loading;
  final VoidCallback? onTap;

  const NexaSharedTile({
    super.key,
    required this.name,
    required this.path,
    required this.subtitle,
    this.isFolder = false,
    this.person,
    this.trailing,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final personName = (person ?? '').trim();
    final avatarName = personName.isEmpty ? 'Shared' : personName;

    return Semantics(
      label: '${isFolder ? 'Folder' : 'File'} $path, shared by $avatarName',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.rowInset,
              vertical: AppDimens.space10,
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SizedBox(
                      width: AppDimens.iconTileLarge,
                      height: AppDimens.iconTileLarge,
                      child: Center(
                        child: isFolder
                            ? const NexaFileGlyph.folder(size: 40)
                            : NexaFileGlyph(name: name, size: 40),
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          shape: BoxShape.circle,
                        ),
                        child: NexaAvatar.small(name: avatarName),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppDimens.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.rowTitle.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppDimens.space4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.bodySmall.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.space8),
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
                  trailing ?? const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
