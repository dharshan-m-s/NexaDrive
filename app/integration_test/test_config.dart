import 'dart:io';

/// Configuration for live-server integration tests.
///
/// These tests log into a real NexaDrive server, so they are driven entirely
/// by environment variables and never by hard-coded credentials or machine
/// paths. They are intentionally NOT part of CI: run them explicitly against
/// a test server:
///
/// ```sh
/// NEXADRIVE_TEST_SERVER=https://your-server  \
/// NEXADRIVE_TEST_USERNAME=admin              \
/// NEXADRIVE_TEST_PASSWORD='change-me'        \
/// flutter test integration_test -d linux
/// ```
class LiveTestConfig {
  const LiveTestConfig(this.serverUrl, this.username, this.password);

  final String serverUrl;
  final String username;
  final String password;

  static const _serverVar = 'NEXADRIVE_TEST_SERVER';
  static const _usernameVar = 'NEXADRIVE_TEST_USERNAME';
  static const _passwordVar = 'NEXADRIVE_TEST_PASSWORD';

  static LiveTestConfig? _fromEnvironment() {
    final env = Platform.environment;
    final server = env[_serverVar]?.trim();
    final username = env[_usernameVar]?.trim();
    final password = env[_passwordVar];
    if (server == null ||
        server.isEmpty ||
        username == null ||
        username.isEmpty ||
        password == null ||
        password.length < 8) {
      return null;
    }
    return LiveTestConfig(server, username, password);
  }

  /// Returns the configured credentials or throws a descriptive error.
  ///
  /// Failing loudly (rather than silently skipping) keeps these tests honest
  /// when an operator explicitly runs them without configuration.
  static LiveTestConfig require() {
    final config = _fromEnvironment();
    if (config == null) {
      throw StateError(
        'Live integration tests require NEXADRIVE_TEST_SERVER, '
        'NEXADRIVE_TEST_USERNAME and NEXADRIVE_TEST_PASSWORD '
        '(at least 8 characters) in the environment. No credentials are '
        'hard-coded, and no machine-specific path is used.',
      );
    }
    return config;
  }
}