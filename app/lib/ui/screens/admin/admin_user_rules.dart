import '../../../services/session.dart';

/// Client-side mirror of the server's account-protection rules.
///
/// This layer exists so the admin UI never *offers* an action the server is
/// going to reject, and so that when a protected account is involved it can
/// explain **why** in plain language instead of surfacing a raw API error.
///
/// It is an affordance only. Authorization is the server's job and the server
/// re-checks every one of these rules (`delete_user`, `update_user`) before it
/// touches the database. A client that lies about [deletionBlocker] still gets
/// a 400/409. Do not move a rule here and delete it there.
///
/// The rules, mirroring `require_admin` + `delete_user` + `update_user` on the
/// server:
///
/// 1. You can never delete the account you are signed in with.
/// 2. The last enabled administrator can never be deleted, demoted, or
///    disabled — that would leave the instance unmanageable.
abstract final class AdminUserRules {
  static bool isAdmin(Map<String, dynamic> user) => user['role'] == 'admin';

  static bool isDisabled(Map<String, dynamic> user) => user['disabled'] == true;

  /// Enabled administrators — the pool rule 2 protects the last one of.
  static int activeAdminCount(List<Map<String, dynamic>> users) =>
      users.where((u) => isAdmin(u) && !isDisabled(u)).length;

  static bool isSelf(Session session, Map<String, dynamic> user) =>
      session.isSelf(
        id: user['id']?.toString(),
        username: user['username']?.toString(),
      );

  /// True when [user] is the only enabled administrator left.
  static bool isLastActiveAdmin(
    List<Map<String, dynamic>> users,
    Map<String, dynamic> user,
  ) =>
      isAdmin(user) &&
      !isDisabled(user) &&
      activeAdminCount(users) <= 1 &&
      _containsUser(users, user);

  /// Human explanation for why [user] cannot be deleted, or `null` when they
  /// can be.
  static String? deletionBlocker(
    Session session,
    List<Map<String, dynamic>> users,
    Map<String, dynamic> user,
  ) {
    if (isSelf(session, user)) {
      return 'This is the account you are signed in with. Sign in as another '
          'administrator to delete it.';
    }
    if (isLastActiveAdmin(users, user)) {
      return 'This is the only administrator left. Deleting it would leave '
          'NexaDrive with no one able to manage users, so it is protected. '
          'Promote another account to administrator first.';
    }
    return null;
  }

  /// Human explanation for why [user] cannot be blocked or demoted, or `null`.
  static String? demotionBlocker(
    Session session,
    List<Map<String, dynamic>> users,
    Map<String, dynamic> user,
  ) {
    if (isSelf(session, user)) {
      return 'You cannot block or demote the account you are signed in with.';
    }
    if (isLastActiveAdmin(users, user)) {
      return 'This is the only administrator left. It cannot be blocked or '
          'demoted, or no one would be able to manage NexaDrive.';
    }
    return null;
  }

  /// Accounts matching [query] on display name, username, or role.
  ///
  /// Case-insensitive, and matches substrings so "gra" finds "Grace Hopper".
  static List<Map<String, dynamic>> filter(
    List<Map<String, dynamic>> users,
    String query,
  ) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return users;
    return users.where((u) {
      final display = u['display_name']?.toString().toLowerCase() ?? '';
      final username = u['username']?.toString().toLowerCase() ?? '';
      final role = u['role']?.toString().toLowerCase() ?? '';
      return display.contains(needle) ||
          username.contains(needle) ||
          role.contains(needle);
    }).toList();
  }

  static bool _containsUser(
    List<Map<String, dynamic>> users,
    Map<String, dynamic> user,
  ) {
    final id = user['id']?.toString();
    if (id != null) {
      return users.any((u) => u['id']?.toString() == id);
    }
    final username = user['username']?.toString();
    return users.any((u) => u['username']?.toString() == username);
  }
}
