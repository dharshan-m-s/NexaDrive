import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/update/semver.dart';

SemVersion v(String value) => SemVersion.tryParse(value)!;

void main() {
  group('SemVersion.tryParse', () {
    test('parses a plain release', () {
      final parsed = v('1.2.3');
      expect(parsed.major, 1);
      expect(parsed.minor, 2);
      expect(parsed.patch, 3);
      expect(parsed.isStable, isTrue);
      expect(parsed.toString(), '1.2.3');
    });

    test('tolerates a leading v (release tag)', () {
      expect(v('v1.2.3').toString(), '1.2.3');
      expect(v('V1.2.3').toString(), '1.2.3');
    });

    test('parses prerelease', () {
      final parsed = v('1.2.0-rc.1');
      expect(parsed.isPrerelease, isTrue);
      expect(parsed.prerelease, 'rc.1');
    });

    test('ignores build metadata', () {
      expect(v('1.2.3+build.42').toString(), '1.2.3');
    });

    test('rejects malformed versions', () {
      expect(SemVersion.tryParse(''), isNull);
      expect(SemVersion.tryParse('abc'), isNull);
      expect(SemVersion.tryParse('1.2'), isNull);
      expect(SemVersion.tryParse('1'), isNull);
      expect(SemVersion.tryParse('1.2.3.4'), isNull);
      expect(SemVersion.tryParse('01.2.3'), isNull);
      expect(SemVersion.tryParse('1.02.3'), isNull);
      expect(SemVersion.tryParse('1.2.03'), isNull);
      expect(SemVersion.tryParse('1.2.3-'), isNull);
      expect(SemVersion.tryParse('1.2.3-rc..1'), isNull);
      expect(SemVersion.tryParse('  '), isNull);
    });
  });

  group('SemVersion precedence (SemVer 2.0.0 rules)', () {
    test('numeric comparison', () {
      expect(v('1.0.0'), lessThan(v('1.0.1')));
      expect(v('1.9.9'), lessThan(v('2.0.0')));
      expect(v('1.2.3'), greaterThan(v('1.2.2')));
    });

    test('prerelease sorts below the release', () {
      expect(v('1.2.0-rc.1'), lessThan(v('1.2.0')));
      expect(v('1.2.0-alpha'), lessThan(v('1.2.0')));
    });

    test('numeric identifiers compare numerically, alpha lexically', () {
      expect(v('1.0.0-alpha.2'), lessThan(v('1.0.0-alpha.10')));
      expect(v('1.0.0-beta'), greaterThan(v('1.0.0-alpha')));
      expect(v('1.0.0-1'), lessThan(v('1.0.0-alpha')));
    });

    test('shorter identifier sets are lower', () {
      expect(v('1.0.0-alpha'), lessThan(v('1.0.0-alpha.1')));
    });

    test('build metadata is ignored for precedence', () {
      expect(v('1.0.0+build1'), equals(v('1.0.0+build2')));
    });

    test('equality', () {
      expect(v('1.0.0'), equals(v('v1.0.0')));
    });
  });

  group('Operators', () {
    test('<, >, <=, >= behave', () {
      final a = v('1.2.0');
      final b = v('1.3.0');
      expect(a < b, isTrue);
      expect(b > a, isTrue);
      expect(a >= v('1.2.0'), isTrue);
      expect(b <= v('1.3.0'), isTrue);
    });
  });
}