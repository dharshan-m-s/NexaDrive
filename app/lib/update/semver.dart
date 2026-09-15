import 'dart:math' as math;

/// Semantic Versioning 2.0.0 for NexaDrive's Update Center.
///
/// Parse and comparison follows https://semver.org:
///  - `MAJOR.MINOR.PATCH[-prerelease][+build]`.
///  - Build metadata is ignored for precedence.
///  - A version with a prerelease has LOWER precedence than the same version
///    without one: `1.2.0-rc.1 < 1.2.0`.
///  - Numeric prerelease identifiers compare as numbers, others as strings;
///    a smaller set of identifiers has lower precedence than a longer set
///    sharing the same prefix (`1.0.0-alpha < 1.0.0-alpha.1`).
class SemVersion implements Comparable<SemVersion> {
  final int major;
  final int minor;
  final int patch;
  final String? prerelease;

  const SemVersion(this.major, this.minor, this.patch, [this.prerelease]);

  /// Whether this version carries a pre-release identifier.
  bool get isPrerelease => prerelease != null && prerelease!.isNotEmpty;

  bool get isStable => !isPrerelease;

  /// Parses a SemVer string. An optional leading `v` is tolerated (release
  /// tags use `v1.2.3`); anything malformed yields [null] so callers can fail
  /// with a precise message instead of crashing.
  static SemVersion? tryParse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    final buildMatch = _buildRe.firstMatch(text);
    if (buildMatch != null) text = text.substring(0, buildMatch.start);

    final dot = text.indexOf('.');
    if (dot <= 0) return null;
    final dash = text.indexOf('-');
    final coreEnd = dash >= 0 ? dash : text.length;
    final core = text.substring(0, coreEnd);
    if (dot >= core.length) return null;

    final majorStr = core.substring(0, dot);
    final rest = core.substring(dot + 1);
    final dot2 = rest.indexOf('.');
    if (dot2 <= 0 || dot2 >= rest.length - 1) return null;
    final minorStr = rest.substring(0, dot2);
    final patchStr = rest.substring(dot2 + 1);

    final major = int.tryParse(majorStr);
    final minor = int.tryParse(minorStr);
    final patch = int.tryParse(patchStr);
    if (major == null || minor == null || patch == null) return null;
    if (major < 0 || minor < 0 || patch < 0) return null;
    // Numeric core fields must not carry leading zeroes.
    if ((majorStr.length > 1 && majorStr.startsWith('0')) ||
        (minorStr.length > 1 && minorStr.startsWith('0')) ||
        (patchStr.length > 1 && patchStr.startsWith('0'))) {
      return null;
    }

    String? prerelease;
    if (dash >= 0) {
      final pre = text.substring(dash + 1);
      if (pre.isEmpty || !_isValidIdentifiers(pre, dotSeparated: true)) {
        return null;
      }
      prerelease = pre;
    }

    return SemVersion(major, minor, patch, prerelease);
  }

  static final RegExp _buildRe = RegExp(r'\+[0-9A-Za-z\-.]*$');
  static final RegExp _identifierRe = RegExp(r'^[0-9A-Za-z-]+$');
  static final RegExp _numericRe = RegExp(r'^[0-9]+$');

  static bool _isValidIdentifiers(String value, {required bool dotSeparated}) {
    final parts = dotSeparated ? value.split('.') : [value];
    if (parts.isEmpty) return false;
    for (final part in parts) {
      if (!_identifierRe.hasMatch(part)) return false;
      // Numeric identifiers must not include leading zeroes.
      if (_numericRe.hasMatch(part) && part.length > 1 && part.startsWith('0')) {
        return false;
      }
    }
    return true;
  }

  /// Full string minus build metadata (the precedence form).
  String get canonical => toString();

  /// `major.minor.patch[-prerelease]`, no leading `v`.
  @override
  String toString() =>
      '$major.$minor.$patch${prerelease != null && prerelease!.isNotEmpty ? '-$prerelease' : ''}';

  String get shortLabel => '$major.$minor';

  @override
  bool operator ==(Object other) =>
      other is SemVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.prerelease == prerelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, prerelease);

  @override
  int compareTo(SemVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    final a = prerelease;
    final b = other.prerelease;
    if (a == b) return 0;
    if (a == null || a.isEmpty) return 1;
    if (b == null || b.isEmpty) return -1;
    return _compareIdentifiers(a.split('.'), b.split('.'));
  }

  bool operator >(SemVersion other) => compareTo(other) > 0;
  bool operator <(SemVersion other) => compareTo(other) < 0;
  bool operator >=(SemVersion other) => compareTo(other) >= 0;
  bool operator <=(SemVersion other) => compareTo(other) <= 0;

  static int _compareIdentifiers(List<String> a, List<String> b) {
    final len = math.max(a.length, b.length);
    for (var i = 0; i < len; i++) {
      final aId = i < a.length ? a[i] : null;
      final bId = i < b.length ? b[i] : null;
      if (aId == null) return -1;
      if (bId == null) return 1;
      final aNum = _numericRe.hasMatch(aId);
      final bNum = _numericRe.hasMatch(bId);
      if (aNum && bNum) {
        final cmp = int.parse(aId).compareTo(int.parse(bId));
        if (cmp != 0) return cmp;
      } else if (aNum != bNum) {
        // Numeric identifiers always have lower precedence than alphanumeric.
        return aNum ? -1 : 1;
      } else {
        final cmp = aId.compareTo(bId);
        if (cmp != 0) return cmp;
      }
    }
    return 0;
  }
}