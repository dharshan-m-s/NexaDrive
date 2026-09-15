import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/update/update_manifest.dart';

Map<String, dynamic> artifact(String url, {String? sha256, int? size}) => {
      'url': url,
      'sha256': sha256 ??
          'a' * 63 + 'b',
      'size': size ?? 1000,
    };

Map<String, dynamic> sampleManifest() => {
      'version': '1.2.0',
      'tag': 'v1.2.0',
      'releaseDate': '2026-09-10T12:00:00Z',
      'prerelease': false,
      'minimumSupportedVersion': '1.0.0',
      'releaseNotes': {
        'New': ['Faster sync'],
        'Fixes': ['Crash on empty folder'],
      },
      'artifacts': {
        'android': {
          'arm64-v8a': {
            'apk': artifact('https://github.com/acme/app/releases/download/v1.2.0/NexaDrive-1.2.0.apk'),
          },
        },
        'windows': {
          'x64': {
            'installer': artifact('https://objects.githubusercontent.com/acme/app/setup.exe'),
            'zip': artifact('https://objects.githubusercontent.com/acme/app/app.zip'),
          },
        },
        'linux': {
          'x64': {
            'appimage': artifact('https://objects.githubusercontent.com/acme/app/app.AppImage'),
            'deb': artifact('https://objects.githubusercontent.com/acme/app/app.deb'),
          },
        },
      },
    };

void main() {
  group('UpdateManifest.fromJson', () {
    test('parses a valid manifest', () {
      final m = UpdateManifest.fromJson(sampleManifest());
      expect(m.version.toString(), '1.2.0');
      expect(m.prerelease, isFalse);
      expect(m.minimumSupportedVersion.toString(), '1.0.0');
      expect(m.releaseNotes.sections.keys, contains('New'));
      expect(m.artifacts['android']!['arm64-v8a']!['apk']!.size, 1000);
    });

    test('round-trips through JSON', () {
      final m = UpdateManifest.fromJson(sampleManifest());
      final back = UpdateManifest.fromJsonString(jsonEncode(m.toJson()));
      expect(back.version, m.version);
      expect(back.tag, m.tag);
      expect(back.releaseDate, m.releaseDate);
      expect(back.artifacts['linux']!['x64']!['deb']!.sha256,
          m.artifacts['linux']!['x64']!['deb']!.sha256);
    });

    test('rejects a missing version', () {
      final json = sampleManifest()..remove('version');
      expect(() => UpdateManifest.fromJson(json),
          throwsA(isA<ManifestParseException>()));
    });

    test('rejects an invalid SemVer version', () {
      final json = sampleManifest()..['version'] = 'not-a-version';
      expect(() => UpdateManifest.fromJson(json),
          throwsA(isA<ManifestParseException>()));
    });

    test('rejects a bad checksum', () {
      final json = sampleManifest();
      (json['artifacts'] as Map)['android'] = {
        'arm64-v8a': {
          'apk': {
            'url': 'https://github.com/a/b.apk',
            'sha256': 'zz-not-hex',
            'size': 12,
          },
        },
      };
      expect(() => UpdateManifest.fromJson(json),
          throwsA(isA<ManifestParseException>()));
    });

    test('rejects a plaintext artifact URL', () {
      final json = sampleManifest();
      final apk = (json['artifacts'] as Map)['android']['arm64-v8a']['apk']
          as Map<String, dynamic>;
      apk['url'] = 'http://github.com/acme/app/NexaDrive.apk';
      expect(() => UpdateManifest.fromJson(json),
          throwsA(isA<ManifestParseException>()));
    });

    test('rejects a zero/negative size', () {
      final json = sampleManifest();
      final apk = (json['artifacts'] as Map)['android']['arm64-v8a']['apk']
          as Map<String, dynamic>;
      apk['size'] = 0;
      expect(() => UpdateManifest.fromJson(json),
          throwsA(isA<ManifestParseException>()));
    });

    test('rejects minimumSupportedVersion newer than version', () {
      final json = sampleManifest()
        ..['minimumSupportedVersion'] = '2.0.0';
      expect(() => UpdateManifest.fromJson(json),
          throwsA(isA<ManifestParseException>()));
    });

    test('sanitizes release notes (strips HTML / control chars)', () {
      final json = sampleManifest()
        ..['releaseNotes'] = {
          'Notes': ['<b>bold</b> and “x”'],
        };
      final m = UpdateManifest.fromJson(json);
      expect(m.releaseNotes.sections['Notes']!.single, 'bold and “x”');
    });

    test('tolerates absent optional fields', () {
      final json = sampleManifest()
        ..remove('releaseNotes')
        ..remove('minimumSupportedVersion');
      final m = UpdateManifest.fromJson(json);
      expect(m.releaseNotes.isEmpty, isTrue);
      expect(m.minimumSupportedVersion, isNull);
      expect(m.minimumServerVersion, isNull);
      expect(m.serverApiVersion, isNull);
    });

    test('parses optional server compatibility fields', () {
      final json = sampleManifest()
        ..['minimumServerVersion'] = '1.0.0'
        ..['serverApiVersion'] = '1.0.0';
      final m = UpdateManifest.fromJson(json);
      expect(m.minimumServerVersion.toString(), '1.0.0');
      expect(m.serverApiVersion, '1.0.0');
      final back = UpdateManifest.fromJsonString(jsonEncode(m.toJson()));
      expect(back.minimumServerVersion.toString(), '1.0.0');
      expect(back.serverApiVersion, '1.0.0');
    });

    test('rejects a bad minimumServerVersion', () {
      final json = sampleManifest()..['minimumServerVersion'] = 'not-semver';
      expect(() => UpdateManifest.fromJson(json),
          throwsA(isA<ManifestParseException>()));
    });

    test('allows minimumServerVersion newer than the client release', () {
      // The manifest pins a *server* requirement; it is fine for a client
      // release to need a newer server deployment than itself.
      final json = sampleManifest()..['minimumServerVersion'] = '2.0.0';
      final m = UpdateManifest.fromJson(json);
      expect(m.minimumServerVersion.toString(), '2.0.0');
    });

    test('rejects a non-string serverApiVersion', () {
      final json = sampleManifest()..['serverApiVersion'] = 7;
      expect(() => UpdateManifest.fromJson(json),
          throwsA(isA<ManifestParseException>()));
    });
  });

  group('ArtifactInfo', () {
    test('hasValidSha256', () {
      const url = 'https://github.com/a/b';
      expect(
        const ArtifactInfo(url, 'deadbeefdeadbeefdeadbeefdeadbeef'
            'deadbeefdeadbeefdeadbeefdeadbeef', 1)
            .hasValidSha256,
        isTrue,
      );
      expect(
        const ArtifactInfo(url, 'nope', 1).hasValidSha256,
        isFalse,
      );
      expect(
        ArtifactInfo(url, 'not hex chars here! ' * 3, 1).hasValidSha256,
        isFalse,
      );
    });
  });
}