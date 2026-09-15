import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'update_manifest.dart';

/// Build-time configuration for the Update Center.
///
/// The defaults point at the project's GitHub releases. CI builds can override
/// the owner/repo with `--dart-define=NEXADRIVE_UPDATE_REPO=owner/repo` (used
/// for prerelease testing before the first public release).
class UpdateConfig {
  /// The canonical production GitHub `owner/repo` that hosts releases and the
  /// manifest. Published client builds are compiled with this value baked in so
  /// users never configure an update source manually.
  static const String defaultRepo = 'dharshan-m-s/NexaDrive';

  static const String repo = String.fromEnvironment(
    'NEXADRIVE_UPDATE_REPO',
    defaultValue: defaultRepo,
  );

  static const String manifestAssetName = 'nexadrive-update-manifest.json';

  /// Hosts the manifest and artifacts are allowed to live on. GitHub redirects
  /// release downloads to `*.githubusercontent.com` (object storage), so both
  /// are accepted; `api.github.com` is *not* used at all. HTTPS only.
  static bool allowsHost(String host) {
    final h = host.toLowerCase();
    return h == 'github.com' || h.endsWith('.githubusercontent.com');
  }

  static String get manifestUrl =>
      'https://github.com/$repo/releases/latest/download/$manifestAssetName';
}

/// Transport for the manifest, with HTTP conditional caching
/// (ETag/Last-Modified) and a strict host allowlist. On a 304 Not Modified the
/// caller keeps using its persisted copy of the manifest (see
/// [UpdateController]); on a network failure it presents the offline state.
class UpdateSource {
  final http.Client _client;
  final Duration timeout;
  final String baseUrl;

  UpdateSource({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? UpdateConfig.manifestUrl;

  Future<void> close() async {
    _client.close();
  }

  /// Fetches the latest manifest. When the caller supplies cache validators
  /// and the server answers 304 Not Modified, the cached manifest is returned
  /// untouched.
  Future<FetchedManifest> fetchLatest({
    String? etag,
    String? lastModified,
  }) async {
    final uri = Uri.parse(baseUrl);
    _assertAllowed(uri);

    final request = http.Request('GET', uri);
    if (etag != null && etag.isNotEmpty) {
      request.headers['If-None-Match'] = etag;
    }
    if (lastModified != null && lastModified.isNotEmpty) {
      request.headers['If-Modified-Since'] = lastModified;
    }

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
    } on SocketException {
      throw const UpdateException(
        UpdateErrorKind.network,
        'No internet connection.',
      );
    } on TimeoutException {
      throw const UpdateException(
        UpdateErrorKind.network,
        'The update check timed out.',
      );
    } on http.ClientException {
      throw const UpdateException(
        UpdateErrorKind.network,
        'Could not reach the update server.',
      );
    } on HandshakeException {
      throw const UpdateException(
        UpdateErrorKind.manifestRejected,
        'The update server certificate could not be verified.',
      );
    }

    var consumed = false;
    try {
      if (response.statusCode == 304) {
        return FetchedManifest.notModified();
      }
      if (response.statusCode == 404 || response.statusCode == 410) {
        throw const UpdateException(
          UpdateErrorKind.notFound,
          'No releases have been published yet.',
        );
      }
      if (response.statusCode != 200) {
        throw UpdateException(
          UpdateErrorKind.http,
          'The update server returned HTTP ${response.statusCode}.',
        );
      }

      // The whole body read is bounded by [timeout] too: a server that sends
      // headers and then stalls mid-body must not leave the Update Center in
      // an undetermined state forever (the classic "Preparing…" hang).
      final body = await response.stream
          .bytesToString()
          .timeout(timeout, onTimeout: () {
        throw const UpdateException(
          UpdateErrorKind.network,
          'The update check timed out while reading the response.',
        );
      });
      consumed = true;
      final manifest = UpdateManifest.fromJsonString(body);
      return FetchedManifest(
        manifest: manifest,
        etag: response.headers['etag'],
        lastModified: response.headers['last-modified'],
      );
    } on ManifestParseException catch (e) {
      throw UpdateException(UpdateErrorKind.malformedManifest, e.message);
    } finally {
      // Release the connection on the error/redirect paths. The body was
      // already fully consumed above on success, so only drain when it was
      // not (a second listen on a single-subscription stream throws
      // synchronously, which must not replace the real outcome).
      if (!consumed) {
        try {
          response.stream.drain<void>().ignore();
        } catch (_) {
          // Nothing left to release.
        }
      }
    }
  }

  /// Verifies an artifact URL before the downloader opens it. Any redirect to
  /// a different host is rejected by the downloader for the same reason.
  Uri resolveArtifact(ArtifactInfo info) {
    final uri = Uri.tryParse(info.url);
    if (uri == null) {
      throw const UpdateException(
        UpdateErrorKind.malformedManifest,
        'Artifact URL is malformed.',
      );
    }
    _assertAllowed(uri);
    return uri;
  }

  void _assertAllowed(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || !UpdateConfig.allowsHost(uri.host)) {
      throw const UpdateException(
        UpdateErrorKind.malformedManifest,
        'Artifact or manifest URL must be HTTPS on an allowed host.',
      );
    }
  }
}

/// Result of a manifest fetch, mirroring the HTTP conditional-cache contract.
class FetchedManifest {
  final UpdateManifest? manifest;
  final String? etag;
  final String? lastModified;
  final bool notModified;

  FetchedManifest({
    this.manifest,
    this.etag,
    this.lastModified,
  }) : notModified = manifest == null;

  FetchedManifest.notModified()
      : manifest = null,
        etag = null,
        lastModified = null,
        notModified = true;

  UpdateManifest requireManifest() {
    final m = manifest;
    if (m == null) {
      throw const UpdateException(
        UpdateErrorKind.malformedManifest,
        'No manifest was returned.',
      );
    }
    return m;
  }
}