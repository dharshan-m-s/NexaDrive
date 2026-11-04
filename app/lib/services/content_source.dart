import 'dart:math' as math;
import 'dart:typed_data';

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

  /// Reads an entire selected document into memory without creating a
  /// local file. Used by the scanner because image decoding and editing
  /// require random access to the compressed image bytes.
  static Future<Uint8List> readAll(String uri, int size) async {
    if (size < 0) {
      throw ArgumentError.value(size, 'size', 'Must be non-negative');
    }
    final builder = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < size) {
      final length = math.min(maxRange, size - offset);
      final chunk = await readRange(uri, offset, length);
      if (chunk.length != length) {
        throw const FormatException(
          'The document ended before all image bytes were read',
        );
      }
      builder.add(chunk);
      offset += length;
    }
    return builder.takeBytes();
  }

  /// Opens a provider stream at [offset]. Native code retains non-seekable
  /// provider pipes so subsequent reads continue sequentially.
  static Future<String> openStream(String uri, int offset) async {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    final sessionId = await _channel.invokeMethod<String>(
      'openSource',
      <String, Object>{'uri': uri, 'offset': offset},
    );
    if (sessionId == null || sessionId.isEmpty) {
      throw const FormatException('The source could not be opened');
    }
    return sessionId;
  }

  /// Reads the next sequential bytes from an open provider stream.
  static Future<Uint8List> readNext(String sessionId, int length) async {
    if (length < 0 || length > maxRange) {
      throw ArgumentError('Invalid content range');
    }
    final data = await _channel.invokeMethod<Uint8List>(
      'readSourceChunk',
      <String, Object>{'sessionId': sessionId, 'length': length},
    );
    if (data == null) {
      throw const FormatException('The source returned no data');
    }
    return data;
  }

  /// Releases the native provider stream, including on cancellation/failure.
  static Future<void> closeStream(String sessionId) async {
    await _channel.invokeMethod<void>(
      'closeSource',
      <String, Object>{'sessionId': sessionId},
    );
  }

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
