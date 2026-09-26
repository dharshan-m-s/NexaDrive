import 'package:flutter/foundation.dart';

import '../../../services/api.dart';
import '../../../services/session.dart';
import 'admin_user_rules.dart';

/// A user row as the Users page consumes it. Normalized once, at the data
/// boundary, so the UI never re-parses raw JSON maps.
class UserProfile {
  final String id;
  final String username;
  final String displayName;
  final bool isAdmin;
  final bool disabled;
  final int? quotaBytes;

  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.isAdmin,
    required this.disabled,
    this.quotaBytes,
  });

  bool get isBlocked => disabled;

  /// Whether this row belongs to the signed-in account.
  bool isSelf(Session session) => AdminUserRules.isSelf(session, _rawSelf());

  Map<String, dynamic> _rawSelf() => {
        'id': id,
        'username': username,
      };

  static UserProfile fromJson(Map<String, dynamic> json) {
    final displayName = json['display_name']?.toString().trim();
    return UserProfile(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: displayName != null && displayName.isNotEmpty
          ? displayName
          : json['username']?.toString() ?? '',
      isAdmin: json['role'] == 'admin',
      disabled: json['disabled'] == true,
      quotaBytes: (json['quota_bytes'] as num?)?.toInt(),
    );
  }
}

/// Aggregate counts for the summary strip.
class UserSummary {
  final int total;
  final int admins;
  final int blocked;

  const UserSummary({
    required this.total,
    required this.admins,
    required this.blocked,
  });
}

/// How a load ended. Failure is never rendered as emptiness.
enum UsersLoadState { loading, ready, failure }

/// State holder for the Users page.
///
/// The page renders from this controller; all mutations flow through it, and
/// every mutation ends in either a refreshed list or an explicit [failure].
class UsersController extends ChangeNotifier {
  final Api api;

  UsersLoadState loadState = UsersLoadState.loading;
  List<UserProfile> users = const [];
  Object? error;
  String query = '';

  /// Monotonic guard against overlapping loads (a slow load answering after a
  /// newer one must not win).
  int _generation = 0;

  UsersController(this.api);

  /// The signed-in session, for self/last-admin protections.
  Session get session => api.session;

  UserSummary get summary {
    return UserSummary(
      total: users.length,
      admins: users.where((u) => u.isAdmin).length,
      blocked: users.where((u) => u.isBlocked).length,
    );
  }

  List<UserProfile> get visible {
    if (query.trim().isEmpty) return users;
    final q = query.trim().toLowerCase();
    return users
        .where((u) =>
            u.username.toLowerCase().contains(q) ||
            u.displayName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> refresh() async {
    final gen = ++_generation;
    loadState = UsersLoadState.loading;
    notifyListeners();
    try {
      final result = await api.users();
      if (gen != _generation) return;
      users = result.map(UserProfile.fromJson).toList();
      error = null;
      loadState = UsersLoadState.ready;
    } catch (e) {
      if (gen != _generation) return;
      error = e;
      loadState = UsersLoadState.failure;
    }
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  /// Wraps a mutation: run it, then refresh. Returns the error message to
  /// surface, or null on success.
  Future<String?> mutate(Future<void> Function() action) async {
    try {
      await action();
      await refresh();
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}

/// Account mutations shared by every editor surface.
extension UsersMutations on UsersController {
  Future<String?> createAccount({
    required String username,
    required String displayName,
    required String password,
    required String role,
    int? quotaBytes,
  }) =>
      mutate(() => api.createUser(
            username: username,
            displayName: displayName,
            password: password,
            role: role,
            quotaBytes: quotaBytes,
          ));

  Future<String?> updateAccount(
    String id, {
    String? displayName,
    String? role,
    bool? disabled,
    int? quotaBytes,
    bool clearQuota = false,
    String? password,
  }) =>
      mutate(() => api.updateUser(
            id,
            displayName: displayName,
            role: role,
            disabled: disabled,
            quotaBytes: quotaBytes,
            clearQuota: clearQuota,
            password: password,
          ));

  Future<String?> deleteAccount(String id) => mutate(() => api.deleteUser(id));
}
