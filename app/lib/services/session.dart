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
  static const _roleKey = 'role';
  static const _themeKey = 'theme_mode';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String? serverUrl;
  String? token;
  String? displayName;
  String? username;
  String? role;
  String themeMode = 'system';

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
    role = prefs.getString(_roleKey) ?? 'user';
    themeMode = prefs.getString(_themeKey) ?? 'system';
    token = await _secure.read(key: _tokenKey);

    // Migrate tokens created by the original Phase 1 scaffold.
    if (token == null) {
      final legacyToken = prefs.getString(_tokenKey);
      if (legacyToken != null && legacyToken.isNotEmpty) {
        token = legacyToken;
        await _secure.write(key: _tokenKey, value: legacyToken);
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
  }) async {
    this.serverUrl = normalizeServerUrl(serverUrl);
    this.token = token;
    this.displayName = displayName;
    this.username = username;
    this.role = role;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, this.serverUrl!);
    await prefs.setString(_displayNameKey, displayName);
    await prefs.setString(_usernameKey, username);
    await prefs.setString(_roleKey, role);
    await _secure.write(key: _tokenKey, value: token);
    await prefs.remove(_tokenKey);
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
    await prefs.remove(_roleKey);
    await prefs.remove(_themeKey);
    await prefs.remove(_tokenKey);
    await _secure.delete(key: _tokenKey);
    serverUrl = null;
    token = null;
    displayName = null;
    username = null;
    role = null;
    themeMode = 'system';
  }
}
