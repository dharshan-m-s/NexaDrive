import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// File-type detection and the shared visual identity for NexaDrive icons.
///
/// Screens never invent folder or file artwork. They ask [FileKind] for the
/// category/format and render it through [NexaFileGlyph], so a PDF looks the
/// same in list, grid, search, shared and dashboard views.
enum Category {
  folder,
  image,
  video,
  audio,
  pdf,
  document,
  archive,
  text,
  unknown
}

/// A finer-grained format used only for icon identity and labels.
enum FileFormat {
  folder,
  image,
  video,
  audio,
  pdf,
  word,
  sheet,
  slides,
  text,
  code,
  archive,
  unknown
}

abstract final class FileKind {
  static const Set<String> _images = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'tif',
    'tiff',
    'svg'
  };
  static const Set<String> _video = {
    'mp4',
    'mov',
    'mkv',
    'webm',
    'avi',
    'm4v',
    '3gp'
  };
  static const Set<String> _audio = {
    'mp3',
    'aac',
    'm4a',
    'wav',
    'flac',
    'ogg',
    'opus',
    'aiff',
    'wma'
  };
  static const Set<String> _doc = {'doc', 'docx', 'odt', 'rtf', 'pages'};
  static const Set<String> _sheet = {'xls', 'xlsx', 'ods', 'csv'};
  static const Set<String> _slides = {'ppt', 'pptx', 'odp', 'key'};
  static const Set<String> _text = {
    'txt',
    'md',
    'markdown',
    'log',
    'nfo',
    'ini',
    'cfg',
    'conf',
    'toml',
  };
  static const Set<String> _code = {
    'json',
    'xml',
    'yaml',
    'yml',
    'html',
    'htm',
    'css',
    'js',
    'jsx',
    'ts',
    'tsx',
    'dart',
    'rs',
    'py',
    'rb',
    'go',
    'java',
    'c',
    'h',
    'cpp',
    'hpp',
    'sh',
    'sql',
  };
  static const Set<String> _archive = {
    'zip',
    'tar',
    'gz',
    'tgz',
    '7z',
    'rar',
    'bz2',
    'xz',
    'zst'
  };

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
    if (_code.contains(e) || _text.contains(e)) return 'text/plain';
    if (_archive.contains(e)) return 'application/zip';
    return 'application/octet-stream';
  }

  static Category category({required String name, required String type}) {
    if (type == 'folder') return Category.folder;
    final format = formatOf(name);
    return switch (format) {
      FileFormat.folder => Category.folder,
      FileFormat.image => Category.image,
      FileFormat.video => Category.video,
      FileFormat.audio => Category.audio,
      FileFormat.pdf => Category.pdf,
      FileFormat.word ||
      FileFormat.sheet ||
      FileFormat.slides =>
        Category.document,
      FileFormat.text || FileFormat.code => Category.text,
      FileFormat.archive => Category.archive,
      FileFormat.unknown => Category.unknown,
    };
  }

  /// The format identity used by the shared glyph component.
  static FileFormat formatOf(String name, {String type = 'file'}) {
    if (type == 'folder') return FileFormat.folder;
    final e = ext(name);
    if (_images.contains(e)) return FileFormat.image;
    if (_video.contains(e)) return FileFormat.video;
    if (_audio.contains(e)) return FileFormat.audio;
    if (e == 'pdf') return FileFormat.pdf;
    if (_doc.contains(e)) return FileFormat.word;
    if (_sheet.contains(e)) return FileFormat.sheet;
    if (_slides.contains(e)) return FileFormat.slides;
    if (_archive.contains(e)) return FileFormat.archive;
    if (_code.contains(e)) return FileFormat.code;
    if (_text.contains(e)) return FileFormat.text;
    return FileFormat.unknown;
  }

  /// A short, restrained mark printed on the document glyph.
  static String formatMark(FileFormat format, [String name = '']) {
    switch (format) {
      case FileFormat.pdf:
        return 'PDF';
      case FileFormat.word:
        return 'DOC';
      case FileFormat.sheet:
        return 'XLS';
      case FileFormat.slides:
        return 'PPT';
      case FileFormat.text:
        return 'TXT';
      case FileFormat.code:
        return '</>';
      case FileFormat.archive:
        final e = ext(name);
        if (e.isNotEmpty && e.length <= 4) return e.toUpperCase();
        return 'ARC';
      case FileFormat.audio:
        return 'AUD';
      case FileFormat.video:
        return 'VID';
      case FileFormat.image:
        return 'IMG';
      case FileFormat.folder:
      case FileFormat.unknown:
        return '';
    }
  }

  /// The single tint for a format, tuned for light and dark warm surfaces.
  static Color formatTint(FileFormat format, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (format) {
      FileFormat.folder =>
        dark ? AppColors.folderOchreDark : AppColors.folderOchreLight,
      FileFormat.pdf => dark ? AppColors.filePdfDark : AppColors.filePdfLight,
      FileFormat.archive =>
        dark ? AppColors.fileArchiveDark : AppColors.fileArchiveLight,
      FileFormat.word =>
        dark ? AppColors.fileWordDark : AppColors.fileWordLight,
      FileFormat.sheet =>
        dark ? AppColors.fileSheetDark : AppColors.fileSheetLight,
      FileFormat.slides =>
        dark ? AppColors.fileSlidesDark : AppColors.fileSlidesLight,
      FileFormat.text =>
        dark ? AppColors.fileTextDark : AppColors.fileTextLight,
      FileFormat.code =>
        dark ? AppColors.fileCodeDark : AppColors.fileCodeLight,
      FileFormat.audio =>
        dark ? AppColors.fileAudioDark : AppColors.fileAudioLight,
      FileFormat.video =>
        dark ? AppColors.fileVideoDark : AppColors.fileVideoLight,
      FileFormat.image =>
        dark ? AppColors.fileImageDark : AppColors.fileImageLight,
      FileFormat.unknown =>
        dark ? AppColors.fileTextDark : AppColors.fileTextLight,
    };
  }

  /// Compatibility helper for code that still asks by [Category].
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

  /// Compatibility tint. New UI uses [formatTint].
  static Color tint(Category category, Brightness brightness) {
    return switch (category) {
      Category.folder => AppColors.accentFor(brightness),
      Category.image => formatTint(FileFormat.image, brightness),
      Category.video => formatTint(FileFormat.video, brightness),
      Category.audio => formatTint(FileFormat.audio, brightness),
      Category.pdf => formatTint(FileFormat.pdf, brightness),
      Category.document => formatTint(FileFormat.text, brightness),
      Category.archive => formatTint(FileFormat.archive, brightness),
      Category.text => formatTint(FileFormat.text, brightness),
      Category.unknown => AppColors.textTertiaryFor(brightness),
    };
  }

  static Color tileFill(Category category, Brightness brightness) {
    final color = tint(category, brightness);
    return brightness == Brightness.dark
        ? color.withValues(alpha: 0.20)
        : color.withValues(alpha: 0.10);
  }

  static Color tintValue(Category category) => tint(category, Brightness.light);

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
