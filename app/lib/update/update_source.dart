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

/// Wraps an [http.Client] so every redirect hop is re-checked against the
/// update host allowlist.
///
/// The stock `http.Client` (IOClient) follows redirects transparently *before*
/// the wrapper sees the reply, so a naive `Location` check in `send` never
/// fires in production. This client disables the inner auto-follow and re-issues
/// each hop itself, rejecting any hop that leaves the HTTPS allowlist or
/// downgrades the scheme.
///
/// The final byte stream must still match the manifest's SHA-256 (the strong
/// guarantee); this closes the "download from an unknown server" hole so an
/// artifact can never be fetched from a host the release never pointed at.
class RedirectGuardedClient extends http.BaseClient {
  RedirectGuardedClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  static const _maxHops = 5;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var current = request;
    for (var hop = 0; ; hop++) {
      // The hop loop below owns redirect handling; keep the inner client from
      // following them on its own. Tests inject clients that ignore this flag
      // and return the raw 3xx, which is exactly what the loop expects.
      current.followRedirects = false;
      current.maxRedirects = 0;
      final response = await _inner.send(current);
      if (!_isRedirect(response)) return response;
      final location = response.headers['location'];
      if (location == null || location.isEmpty) return response;
      if (hop >= _maxHops) {
        await _drain(response);
        throw const UpdateException(
          UpdateErrorKind.manifestRejected,
          'The download address redirected too many times.',
        );
      }
      final target = current.url.resolveUri(Uri.parse(location));
      if (!UpdateConfig.allowsHost(target.host)) {
        await _drain(response);
        throw const UpdateException(
          UpdateErrorKind.manifestRejected,
          'The download address redirected outside the official release '
          'servers.',
        );
      }
      // resolveUri preserves the scheme of a relative Location, but a crafted
      // "http://github.com/..." would slip through the allowlist alone.
      if (target.scheme != 'https') {
        await _drain(response);
        throw const UpdateException(
          UpdateErrorKind.manifestRejected,
          'The download address redirected to a non-HTTPS server.',
        );
      }
      await _drain(response);
      current = _reissue(current, target);
    }
  }

  static bool _isRedirect(http.StreamedResponse response) {
    final status = response.statusCode;
    return status == 301 ||
        status == 302 ||
        status == 303 ||
        status == 307 ||
        status == 308;
  }

  static Future<void> _drain(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>();
    } catch (_) {
      // Nothing left to release.
    }
  }

  /// Rebuilds [request] for [target], preserving method, headers, and body.
  static http.BaseRequest _reissue(http.BaseRequest request, Uri target) {
    final next = http.Request(request.method, target)
      ..followRedirects = false
      ..maxRedirects = 0;
    request.headers.forEach((k, v) => next.headers[k] = v);
    if (request is http.Request) {
      final bodyBytes = request.bodyBytes;
      if (bodyBytes.isNotEmpty) next.bodyBytes = bodyBytes;
    }
    return next;
  }

  @override
  void close() => _inner.close();
}

/// Transport for the manifest, with HTTP conditional caching
/// every redirect hop (see [RedirectGuardedClient]), and a strict host
  /// allowlist. On a 304 Not Modified the caller keeps using its persisted copy
  /// of the manifest (see [UpdateController]); on a network failure it presents
  /// the offline state.
class UpdateSource {
  final http.Client _client;
  final Duration timeout;
  final String baseUrl;

  UpdateSource({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    String? baseUrl,
  })  : _client = RedirectGuardedClient(client ?? http.Client()),
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