import 'package:flutter/material.dart';

/// File-type detection and icon mapping for the NexaDrive file browser.
///
/// Keeps the One UI visual language by mapping MIME/extension categories to a
/// single neutral document icon with a category tint + label, instead of a
/// colorful icon per extension.
/// The One UI-neutral category for a file.
enum Category { folder, image, video, audio, pdf, document, archive, text, unknown }

abstract final class FileKind {
  static const Set<String> _images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'tif', 'tiff'};
  static const Set<String> _video = {'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', '3gp'};
  static const Set<String> _audio = {'mp3', 'aac', 'm4a', 'wav', 'flac', 'ogg', 'opus', 'aiff', 'wma'};
  static const Set<String> _doc = {'doc', 'docx', 'odt', 'rtf', 'pages'};
  static const Set<String> _sheet = {'xls', 'xlsx', 'ods', 'csv'};
  static const Set<String> _slides = {'ppt', 'pptx', 'odp', 'key'};
  static const Set<String> _text = {'txt', 'md', 'markdown', 'log', 'json', 'xml', 'yaml', 'yml', 'conf', 'ini', 'cfg', 'toml', 'csv', 'html', 'htm', 'css', 'js', 'ts', 'dart', 'rs', 'py', 'rb', 'go', 'java', 'c', 'h', 'cpp', 'hpp', 'sh', 'sql', 'nfo'};
  static const Set<String> _archive = {'zip', 'tar', 'gz', 'tgz', '7z', 'rar', 'bz2', 'xz', 'zst'};

  /// Returns the lowercase extension without the leading dot.
  static String ext(String filename) {
    final i = filename.lastIndexOf('.');
    if (i < 0 || i == filename.length - 1) return '';
    return filename.substring(i + 1).toLowerCase();
  }

  static String mimeFor({required String name, required String type}) {
    if (type == 'folder') return 'application/vnd.nexadrive.folder';
    final e = ext(name);
    if (_images.contains(e)) {
      if (e == 'svg') return 'image/svg+xml';
      if (e == 'heic' || e == 'heif') return 'image/heic';
      if (e == 'webp') return 'image/webp';
      if (e == 'bmp') return 'image/bmp';
      if (e == 'tif' || e == 'tiff') return 'image/tiff';
      if (e == 'gif') return 'image/gif';
      return 'image/jpeg';
    }
    if (_video.contains(e)) return 'video/mp4';
    if (_audio.contains(e)) return 'audio/mpeg';
    if (e == 'pdf') return 'application/pdf';
    if (_doc.contains(e)) return 'application/msword';
    if (_sheet.contains(e)) return 'application/vnd.ms-excel';
    if (_slides.contains(e)) return 'application/vnd.ms-powerpoint';
    if (_text.contains(e)) return 'text/plain';
    if (_archive.contains(e)) return 'application/zip';
    return 'application/octet-stream';
  }

  static Category category({required String name, required String type}) {
    if (type == 'folder') return Category.folder;
    final e = ext(name);
    if (_images.contains(e)) return Category.image;
    if (_video.contains(e)) return Category.video;
    if (_audio.contains(e)) return Category.audio;
    if (e == 'pdf') return Category.pdf;
    if (_doc.contains(e) || _sheet.contains(e) || _slides.contains(e)) return Category.document;
    if (_archive.contains(e)) return Category.archive;
    if (_text.contains(e)) return Category.text;
    return Category.unknown;
  }

  /// Icon for a file category — neutral document shapes, tinted by category
  /// using a muted accent (One UI keeps file icons calm).
  static IconData icon(Category category) {
    switch (category) {
      case Category.folder:
        return Icons.folder_rounded;
      case Category.image:
        return Icons.image_rounded;
      case Category.video:
        return Icons.movie_rounded;
      case Category.audio:
        return Icons.music_note_rounded;
      case Category.pdf:
        return Icons.picture_as_pdf_rounded;
      case Category.document:
        return Icons.description_rounded;
      case Category.archive:
        return Icons.folder_zip_rounded;
      case Category.text:
        return Icons.article_rounded;
      case Category.unknown:
        return Icons.insert_drive_file_rounded;
    }
  }

  /// Tint for the neutral icon.
  static Color tint(Category category, Brightness brightness) {
    switch (category) {
      case Category.folder:
        return const Color(0xFF0B87D0); // soft accent blue
      case Category.image:
        return const Color(0xFFB25E00); // muted amber
      case Category.video:
        return const Color(0xFF8E24AA); // muted purple
      case Category.audio:
        return const Color(0xFF00897B); // muted teal
      case Category.pdf:
        return const Color(0xFFC62828); // one UI error-red accent
      case Category.document:
        return const Color(0xFF5B5F66); // neutral gray
      case Category.archive:
        return const Color(0xFF6D4C41); // muted brown
      case Category.text:
        return const Color(0xFF455A64); // cool slate
      case Category.unknown:
        return const Color(0xFF8A9099);
    }
  }

  /// Tile fill used behind the category icon (soft, low-contrast).
  static Color tileFill(Category category, Brightness brightness) {
    final tint = tintValue(category);
    return brightness == Brightness.dark
        ? (tint.withValues(alpha: 0.20))
        : (tint.withValues(alpha: 0.12));
  }

  static Color tintValue(Category category) {
    switch (category) {
      case Category.folder:
        return const Color(0xFF0B87D0);
      case Category.image:
        return const Color(0xFFB25E00);
      case Category.video:
        return const Color(0xFF8E24AA);
      case Category.audio:
        return const Color(0xFF00897B);
      case Category.pdf:
        return const Color(0xFFC62828);
      case Category.document:
        return const Color(0xFF5B5F66);
      case Category.archive:
        return const Color(0xFF6D4C41);
      case Category.text:
        return const Color(0xFF455A64);
      case Category.unknown:
        return const Color(0xFF8A9099);
    }
  }

  /// Human-readable category label for accessibility and metadata.
  static String label(Category category) {
    switch (category) {
      case Category.folder:
        return 'Folder';
      case Category.image:
        return 'Image';
      case Category.video:
        return 'Video';
      case Category.audio:
        return 'Audio';
      case Category.pdf:
        return 'PDF';
      case Category.document:
        return 'Document';
      case Category.archive:
        return 'Archive';
      case Category.text:
        return 'Text';
      case Category.unknown:
        return 'File';
    }
  }

  /// Whether NexaDrive can render this file in-app.
  static bool isPreviewable(Category category) {
    switch (category) {
      case Category.image:
      case Category.text:
      case Category.pdf:
        return true;
      default:
        return false;
    }
  }

  static bool isPlayable(Category category) {
    switch (category) {
      case Category.video:
      case Category.audio:
        return true;
      default:
        return false;
    }
  }
}