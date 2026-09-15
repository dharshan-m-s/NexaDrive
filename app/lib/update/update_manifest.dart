import 'dart:convert';
import 'semver.dart';

/// Thrown when a manifest (or one of its artifact entries) fails validation.
class ManifestParseException implements Exception {
  final String message;
  ManifestParseException(this.message);

  @override
  String toString() => message;
}

/// A single downloadable artifact: HTTPS URL plus expected SHA-256 and size.
class ArtifactInfo {
  final String url;
  final String sha256;
  final int size;

  const ArtifactInfo(this.url, this.sha256, this.size);

  bool get hasValidSha256 => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256);

  String get sha256Hex => sha256.toLowerCase();

  Map<String, dynamic> toJson() => {'url': url, 'sha256': sha256, 'size': size};

  static ArtifactInfo fromJson(Map<String, dynamic> json, String context) {
    final url = json['url'];
    final sha256 = json['sha256'];
    final size = json['size'];
    if (url is! String || url.isEmpty) {
      throw ManifestParseException('$context: "url" must be a non-empty string');
    }
    if (!_uriLooksHttps(url)) {
      throw ManifestParseException('$context: "url" must be an https URL');
    }
    if (sha256 is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) {
      throw ManifestParseException('$context: "sha256" must be a 64-char hex digest');
    }
    if (size is! int || size <= 0) {
      throw ManifestParseException('$context: "size" must be a positive integer');
    }
    return ArtifactInfo(
      url.trim(),
      sha256.toLowerCase(),
      size,
    );
  }

  static bool _uriLooksHttps(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.isScheme('https') && uri.host.isNotEmpty;
  }
}

/// A structured release-notes payload. Section keys are free-form; the UI
/// renders each list as plain text bullets (never HTML).
class ReleaseNotes {
  final Map<String, List<String>> sections;

  const ReleaseNotes(this.sections);

  bool get isEmpty => sections.isEmpty;

  int get totalItems =>
      sections.values.fold(0, (sum, items) => sum + items.length);

  Map<String, dynamic> toJson() => {
        for (final entry in sections.entries)
          entry.key: entry.value,
      };

  static ReleaseNotes fromJson(Object? json) {
    if (json == null) return const ReleaseNotes({});
    if (json is! Map<String, dynamic>) {
      throw ManifestParseException('"releaseNotes" must be an object of lists');
    }
    final sections = <String, List<String>>{};
    for (final entry in json.entries) {
      final value = entry.value;
      final items = <String>[];
      if (value is List) {
        for (final item in value) {
          if (item is! String) {
            throw ManifestParseException(
                '"releaseNotes.${entry.key}" entries must be strings');
          }
          items.add(_sanitizeText(item));
        }
      } else if (value is String && value.trim().isNotEmpty) {
        // A single string is treated as one bullet for hand-written manifests.
        items.add(_sanitizeText(value));
      }
      if (items.isNotEmpty) sections[entry.key] = items;
    }
    return ReleaseNotes(sections);
  }

  /// Keeps release notes as inert plain text: strip control characters and
  /// anything that could be interpreted as markdown links or HTML.
  static String _sanitizeText(String raw) {
    final noControl = raw.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    final noHtml = noControl.replaceAll(RegExp(r'<[^>]*>'), '');
    return noHtml.trim();
  }
}

/// The published Update Center manifest
/// (`nexadrive-update-manifest.json` on a GitHub release).
class UpdateManifest {
  final SemVersion version;
  final String tag;
  final DateTime releaseDate;
  final bool prerelease;
  final SemVersion? minimumSupportedVersion;

  /// Minimum server release a client running this version can talk to. When
  /// set, the app warns the user to update the server if the running instance
  /// is older.
  final SemVersion? minimumServerVersion;

  /// Backward-compatibility API surface this client expects from the server
  /// (`/api/server/status` returns `api_version`). Absent means "any".
  final String? serverApiVersion;
  final ReleaseNotes releaseNotes;

  /// Platform → architecture → installer kind → artifact.
  ///   android: arm64-v8a|armeabi-v7a|x86|x86_64 → apk
  ///   windows: x64 → installer, zip
  ///   linux:   x64|aarch64 → appimage, deb
  final Map<String, Map<String, Map<String, ArtifactInfo>>> artifacts;

  UpdateManifest({
    required this.version,
    required this.tag,
    required this.releaseDate,
    required this.prerelease,
    required this.minimumSupportedVersion,
    this.minimumServerVersion,
    this.serverApiVersion,
    required this.releaseNotes,
    required this.artifacts,
  });

  /// Resolves the right artifact for a platform and architecture, or null when
  /// no installable artifact is published for this device.
  ArtifactInfo? artifactFor(String platform, String arch, String kind) {
    final platformArtifacts = artifacts[platform];
    if (platformArtifacts == null) return null;
    return platformArtifacts[arch]?[kind];
  }

  static const List<String> supportedPlatforms = ['android', 'windows', 'linux'];

  Map<String, dynamic> toJson() => {
        'version': version.toString(),
        'tag': tag,
        'releaseDate': releaseDate.toUtc().toIso8601String(),
        'prerelease': prerelease,
        'minimumSupportedVersion': minimumSupportedVersion?.toString(),
        if (minimumServerVersion != null)
          'minimumServerVersion': minimumServerVersion!.toString(),
        if (serverApiVersion != null) 'serverApiVersion': serverApiVersion,
        'releaseNotes': releaseNotes.toJson(),
        'artifacts': {
          for (final p in artifacts.entries)
            p.key: {
              for (final a in p.value.entries)
                a.key: {
                  for (final k in a.value.entries) k.key: k.value.toJson(),
                },
            },
        },
      };

  static UpdateManifest fromJsonString(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw ManifestParseException('Manifest is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw ManifestParseException('Manifest root must be a JSON object');
    }
    return fromJson(decoded);
  }

  static UpdateManifest fromJson(Map<String, dynamic> json) {
    final versionStr = json['version'];
    if (versionStr is! String) {
      throw ManifestParseException('Missing or invalid "version"');
    }
    final version = SemVersion.tryParse(versionStr);
    if (version == null) {
      throw ManifestParseException('"version" is not a valid SemVer: $versionStr');
    }

    final tag = json['tag'];
    if (tag is! String || tag.isEmpty) {
      throw ManifestParseException('Missing or invalid "tag"');
    }

    final releaseDateStr = json['releaseDate'];
    if (releaseDateStr is! String) {
      throw ManifestParseException('Missing or invalid "releaseDate"');
    }
    final releaseDate = DateTime.tryParse(releaseDateStr);
    if (releaseDate == null) {
      throw ManifestParseException('"releaseDate" is not a valid date');
    }

    final prerelease = json['prerelease'];
    if (prerelease is! bool) {
      throw ManifestParseException('Missing or invalid "prerelease"');
    }

    SemVersion? minimumSupported;
    final minStr = json['minimumSupportedVersion'];
    if (minStr != null) {
      if (minStr is! String) {
        throw ManifestParseException('"minimumSupportedVersion" must be a string');
      }
      minimumSupported = SemVersion.tryParse(minStr);
      if (minimumSupported == null) {
        throw ManifestParseException(
            '"minimumSupportedVersion" is not valid SemVer: $minStr');
      }
      if (version < minimumSupported) {
        // Publishing this state would make the release impossible to install.
        throw ManifestParseException(
            '"minimumSupportedVersion" ($minimumSupported) is newer than "version"');
      }
    }

    final releaseNotes = ReleaseNotes.fromJson(json['releaseNotes']);

    SemVersion? minimumServer;
    final minServerStr = json['minimumServerVersion'];
    if (minServerStr != null) {
      if (minServerStr is! String) {
        throw ManifestParseException('"minimumServerVersion" must be a string');
      }
      minimumServer = SemVersion.tryParse(minServerStr);
      if (minimumServer == null) {
        throw ManifestParseException(
            '"minimumServerVersion" is not valid SemVer: $minServerStr');
      }
    }

    final serverApi = json['serverApiVersion'];
    if (serverApi != null && serverApi is! String) {
      throw ManifestParseException('"serverApiVersion" must be a string');
    }

    final artifactsJson = json['artifacts'];
    if (artifactsJson == null) {
      throw ManifestParseException('Missing "artifacts" object');
    }
    if (artifactsJson is! Map<String, dynamic>) {
      throw ManifestParseException('"artifacts" must be an object');
    }

    final artifacts = <String, Map<String, Map<String, ArtifactInfo>>>{};
    artifactsJson.forEach((platform, archMap) {
      if (archMap is! Map<String, dynamic>) {
        throw ManifestParseException('artifacts.$platform must be an object');
      }
      final archs = <String, Map<String, ArtifactInfo>>{};
      archMap.forEach((arch, kinds) {
        if (kinds is! Map<String, dynamic> || kinds.isEmpty) {
          throw ManifestParseException(
              'artifacts.$platform.$arch must be a non-empty object');
        }
        final parsed = <String, ArtifactInfo>{};
        kinds.forEach((kind, value) {
          if (value is! Map<String, dynamic>) {
            throw ManifestParseException(
                'artifacts.$platform.$arch.$kind must be an object');
          }
          parsed[kind] = ArtifactInfo.fromJson(
            value,
            'artifacts.$platform.$arch.$kind',
          );
        });
        archs[arch] = parsed;
      });
      artifacts[platform] = archs;
    });

    return UpdateManifest(
      version: version,
      tag: tag,
      releaseDate: releaseDate,
      prerelease: prerelease,
      minimumSupportedVersion: minimumSupported,
      minimumServerVersion: minimumServer,
      serverApiVersion: serverApi as String?,
      releaseNotes: releaseNotes,
      artifacts: artifacts,
    );
  }

  @override
  String toString() => 'UpdateManifest($version, $tag, ${artifacts.length} platforms)';
}

/// Error kinds the controller understands (kept dependency-free so tests can
/// assert on them precisely).
class UpdateException implements Exception {
  final UpdateErrorKind kind;
  final String message;
  const UpdateException(this.kind, this.message);

  @override
  String toString() => message;
}

enum UpdateErrorKind {
  network,
  http,
  malformedManifest,
  manifestRejected,
  notFound,
  unsupportedPlatform,
  unsupportedArchitecture,
  noArtifact,
  checksumMismatch,
  sizeMismatch,
  installFailed,
  blocked,
  cancelled,
}