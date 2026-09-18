import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Session extends ChangeNotifier {
  static const _tokenKey = 'token';

  /// Normalizes a server address for storage and requests. Explicit schemes
  /// are preserved; when none is given, HTTPS is assumed (never an implicit
  /// cleartext HTTP). Local LAN servers that are HTTP-only must type the
  /// scheme explicitly, e.g. `http://<lan-ip>:8080`.
  static String normalizeServerUrl(String value) {
    var url = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return url;
    if (!url.contains('://')) {
      url = 'https://$url';
    }
    return url.replaceAll(RegExp(r'/+$'), '');
  }

  static const _serverKey = 'server_url';
  static const _displayNameKey = 'display_name';
  static const _usernameKey = 'username';
  static const _userIdKey = 'user_id';
  static const _roleKey = 'role';
  static const _themeKey = 'theme_mode';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String? serverUrl;
  String? token;
  String? displayName;
  String? username;

  /// Server-assigned id of the signed-in account.
  ///
  /// The admin screens need it to recognise "the account you are signed in
  /// with" — that row must not offer a destructive action the server will
  /// reject. It is a display affordance only: the server independently
  /// refuses self-deletion and last-admin deletion. Sessions created before
  /// this field was persisted simply have `null` here and fall back to
  /// matching on [username].
  String? userId;

  String? role;
  String themeMode = 'system';

  /// True when [candidate] identifies the signed-in account, matching on id
  /// when known and falling back to a case-insensitive username compare (the
  /// server treats login keys case-insensitively).
  bool isSelf({String? id, String? username}) {
    if (id != null && userId != null) return id == userId;
    final mine = this.username?.trim().toLowerCase();
    if (mine == null || mine.isEmpty) return false;
    return username?.trim().toLowerCase() == mine;
  }

  /// Cache namespace for on-disk thumbnails and cached media.
  ///
  /// Includes the signed-in account, not just the server: two users on the
  /// same server have identical relative paths ("Camera/IMG_1.jpg"), so a
  /// server-only key would let one account read another's cached previews on a
  /// shared device.
  String get cacheNamespace => '${serverUrl ?? ''}#${username ?? ''}';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    serverUrl = prefs.getString(_serverKey);
    displayName = prefs.getString(_displayNameKey);
    username = prefs.getString(_usernameKey);
    userId = prefs.getString(_userIdKey);
    role = prefs.getString(_roleKey) ?? 'user';
    themeMode = prefs.getString(_themeKey) ?? 'system';
    token = await _readToken();

    // Migrate tokens created by the original Phase 1 scaffold. The legacy copy
    // is moved into the keystore and then removed from plaintext storage.
    if (token == null) {
      final legacyToken = prefs.getString(_tokenKey);
      if (legacyToken != null && legacyToken.isNotEmpty) {
        token = legacyToken;
        await _writeToken(legacyToken);
        await prefs.remove(_tokenKey);
      }
    }
  }

  Future<void> save({
    required String serverUrl,
    required String token,
    required String displayName,
    required String username,
    required String role,
    String? userId,
  }) async {
    this.serverUrl = normalizeServerUrl(serverUrl);
    this.token = token;
    this.displayName = displayName;
    this.username = username;
    this.userId = userId;
    this.role = role;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, this.serverUrl!);
    await prefs.setString(_displayNameKey, displayName);
    await prefs.setString(_usernameKey, username);
    await prefs.setString(_roleKey, role);
    if (userId == null) {
      await prefs.remove(_userIdKey);
    } else {
      await prefs.setString(_userIdKey, userId);
    }
    await _writeToken(token);
    await prefs.remove(_tokenKey);
  }

  /// Reads the session token from the platform keystore.
  ///
  /// A platform without a secret service (headless or minimally installed
  /// Linux, where libsecret has no running keyring) must degrade to "not signed
  /// in yet". Letting the exception escape would crash the app before its
  /// first frame, which is indistinguishable from a broken build.
  Future<String?> _readToken() async {
    try {
      return await _secure.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  /// Persists the session token, or leaves the session memory-only.
  ///
  /// There is deliberately no plaintext fallback: the product rule is that
  /// session tokens are never stored in the clear, so an unavailable keystore
  /// means the user signs in again next launch.
  Future<void> _writeToken(String token) async {
    try {
      await _secure.write(key: _tokenKey, value: token);
    } catch (_) {
      // Keystore unavailable; the current session still works.
    }
  }

  Future<void> setThemeMode(String value) async {
    if (!{'system', 'light', 'dark'}.contains(value)) return;
    themeMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, value);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serverKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_themeKey);
    await prefs.remove(_tokenKey);
    try {
      await _secure.delete(key: _tokenKey);
    } catch (_) {
      // Nothing persisted to remove.
    }
    serverUrl = null;
    token = null;
    displayName = null;
    username = null;
    userId = null;
    role = null;
    themeMode = 'system';
  }
}
