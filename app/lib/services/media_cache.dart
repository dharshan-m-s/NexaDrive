import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Removes the old on-disk media cache.
///
/// Earlier builds copied audio tracks into an app cache directory so the
/// platform backend could play and seek them. Media is now streamed straight
/// from the server, so no client-side media file may remain: this helper
/// deletes any cache left behind by those builds.
class MediaCache {
  static const _dirName = 'media';

  /// Deletes legacy cached media. Best-effort: a missing directory or a
  /// filesystem error never blocks startup or sign-out.
  static Future<void> purgeLegacy() async {
    try {
      final base = await getApplicationCacheDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}$_dirName');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
