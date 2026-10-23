import 'package:flutter/services.dart';

/// Reads bytes directly from an Android Storage Access Framework document.
///
/// Folder uploads store the document URI in the queue instead of copying the
/// tree into app storage. The Android host opens the provider stream on demand
/// and returns exactly one chunk, so a multi-gigabyte folder never occupies
/// cache space.
///
/// The channel is served by `MainActivity`, which is available while the app
/// is in the foreground. The background worker deliberately leaves URI-backed
/// items queued for the next foreground run rather than failing them.
class ContentSource {
  const ContentSource._();

  static const MethodChannel _channel =
      MethodChannel('nexadrive/folder_picker');

  /// Largest range the host will read in one call.
  static const int maxRange = 4 * 1024 * 1024;

  /// Reads [length] bytes starting at [offset] from [uri].
  ///
  /// Throws a [PlatformException] when the document moved, the grant was
  /// revoked, or the provider cannot serve the range.
  static Future<Uint8List> readRange(
    String uri,
    int offset,
    int length,
  ) async {
    if (offset < 0 || length < 0 || length > maxRange) {
      throw ArgumentError('Invalid content range');
    }
    final data = await _channel.invokeMethod<Uint8List>(
      'readSourceRange',
      <String, Object>{
        'uri': uri,
        'offset': offset,
        'length': length,
      },
    );
    if (data == null) {
      throw const FormatException('The source returned no data');
    }
    return data;
  }
}
