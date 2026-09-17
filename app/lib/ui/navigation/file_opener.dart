import 'package:flutter/material.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/models/file_entry.dart';
import '../../core/utils/file_kind.dart';
import '../../services/api.dart';
import '../../services/image_pipeline.dart';
import '../screens/files/file_share_sheet.dart';
import '../screens/files/files_screen.dart';
import '../screens/media/audio_player_screen.dart';
import '../screens/media/video_player_screen.dart';
import '../screens/photos/photo_viewer.dart';
import '../screens/viewers/pdf_viewer_screen.dart';
import '../screens/viewers/text_viewer_screen.dart';
import '../widgets/one_ui_sheet.dart';

/// The one place that decides how a file is opened.
///
/// Every screen (Files, Search, Shared, Home, Trash) routes through here so
/// tapping the same file never produces a different experience depending on
/// where it was tapped from.
abstract final class FileOpener {
  /// Opens [entry].
  ///
  /// [siblings] lets the photo viewer swipe between the other images in the
  /// same listing. [images] should be the caller's shared [ImageRepository] so
  /// the viewer reuses an already-warm, bounded cache.
  static Future<void> open(
    BuildContext context, {
    required Api api,
    required FileEntry entry,
    List<FileEntry> siblings = const [],
    ImageRepository? images,
  }) async {
    switch (entry.category) {
      case Category.image:
        return openPhoto(
          context,
          api: api,
          entry: entry,
          siblings: siblings,
          images: images,
        );
      case Category.video:
        return _push(context, VideoPlayerScreen(file: entry, api: api));
      case Category.audio:
        // Pass the surrounding tracks so the player has a real queue.
        final tracks = siblings
            .where((e) => e.category == Category.audio && !e.isFolder)
            .toList(growable: false);
        return _push(
          context,
          AudioPlayerScreen(
            file: entry,
            api: api,
            playlist: tracks.isEmpty ? [entry] : tracks,
          ),
        );
      case Category.pdf:
        return _push(context, PdfViewerScreen(file: entry, api: api));
      case Category.text:
        return _push(context, TextViewerScreen(file: entry, api: api));
      case Category.folder:
        // Folders open scoped to that folder, so a search result is usable.
        return _push(context, FilesScreen(api: api, initialPath: entry.path));
      case Category.archive:
      case Category.document:
      case Category.unknown:
        return _showUnsupported(context, api: api, entry: entry);
    }
  }

  /// Opens the full-resolution photo viewer for [entry].
  static Future<void> openPhoto(
    BuildContext context, {
    required Api api,
    required FileEntry entry,
    List<FileEntry> siblings = const [],
    ImageRepository? images,
  }) {
    final gallery = <FileEntry>[
      ...siblings.where((e) => e.category == Category.image && !e.isFolder),
    ];
    if (!gallery.any((e) => e.path == entry.path)) gallery.insert(0, entry);
    final index = gallery.indexWhere((e) => e.path == entry.path);
    final repository = images ?? ImageRepository(api);
    return _push(
      context,
      PhotoViewer(
        photos: gallery.map((e) => e.toJson()).toList(growable: false),
        initialIndex: index < 0 ? 0 : index,
        api: api,
        images: repository,
      ),
    );
  }

  static Future<void> _push(BuildContext context, Widget screen) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  /// Formats NexaDrive cannot render in-app, plus previewable-in-principle
  /// files the user chose to hand to another app.
  static Future<void> _showUnsupported(
    BuildContext context, {
    required Api api,
    required FileEntry entry,
  }) async {
    await showOneUiSheet<void>(
      context,
      builder: (sheetContext) => OneUiSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OneUiSheetHeader(
              title: entry.name,
              subtitle: '${FileKind.label(entry.category)} · Not viewable here',
            ),
            Text(
              'NexaDrive can\u2019t open ${FileKind.label(entry.category).toLowerCase()} '
              'files in the app. Share it, or save it and open it with another app.',
              style: AppTextStyle.rowSubtitle.copyWith(
                color: AppColors.textSecondaryFor(Theme.of(sheetContext).brightness),
              ),
            ),
            const SizedBox(height: AppDimens.space20),
            FilledButton.icon(
              icon: const Icon(Icons.share_outlined, size: AppDimens.iconSmall),
              label: const Text('Share link'),
              onPressed: () {
                Navigator.pop(sheetContext);
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => FileShareSheet(api: api, files: [entry]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
