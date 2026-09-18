import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/admin/admin_user_rules.dart';

void main() {
  Session session({String? id, String? username}) {
    final s = Session()
      ..serverUrl = 'https://example.com'
      ..token = 'tok'
      ..username = username;
    s.userId = id;
    return s;
  }

  Map<String, dynamic> user({
    required String id,
    required String username,
    String? displayName,
    String role = 'user',
    bool disabled = false,
    int? quotaBytes,
  }) =>
      {
        'id': id,
        'username': username,
        'display_name': displayName ?? username,
        'role': role,
        'disabled': disabled,
        'quota_bytes': quotaBytes,
      };

  group('isSelf', () {
    test('matches on id when both sides know it', () {
      final s = session(id: 'u1', username: 'ada');
      expect(AdminUserRules.isSelf(s, user(id: 'u1', username: 'ada')), isTrue);
      expect(AdminUserRules.isSelf(s, user(id: 'u2', username: 'grace')), isFalse);
    });

    test('id match wins even if the username differs (renamed account)', () {
      final s = session(id: 'u1', username: 'old-name');
      expect(
        AdminUserRules.isSelf(s, user(id: 'u1', username: 'new-name')),
        isTrue,
      );
    });

    test('falls back to a case-insensitive username for legacy sessions', () {
      // Sessions created before the id was persisted have userId == null.
      final s = session(username: 'Ada');
      expect(AdminUserRules.isSelf(s, user(id: 'x', username: 'ada')), isTrue);
      expect(AdminUserRules.isSelf(s, user(id: 'x', username: 'ADA')), isTrue);
      expect(AdminUserRules.isSelf(s, user(id: 'x', username: 'grace')), isFalse);
    });

    test('is false when the session knows nothing to match on', () {
      final s = session();
      expect(AdminUserRules.isSelf(s, user(id: 'u1', username: 'ada')), isFalse);
    });

    test('does not match an account with a missing username', () {
      final s = session(id: 'u1');
      expect(
        AdminUserRules.isSelf(s, {'id': 'u2'}),
        isFalse,
        reason: 'null == null must not read as "this is me"',
      );
    });
  });

  group('activeAdminCount', () {
    test('counts only enabled administrators', () {
      expect(
        AdminUserRules.activeAdminCount([
          user(id: '1', username: 'a', role: 'admin'),
          user(id: '2', username: 'b', role: 'admin', disabled: true),
          user(id: '3', username: 'c'),
        ]),
        1,
      );
    });
  });

  group('isLastActiveAdmin', () {
    test('true for the only enabled administrator', () {
      final users = [
        user(id: '1', username: 'root', role: 'admin'),
        user(id: '2', username: 'grace'),
      ];
      expect(AdminUserRules.isLastActiveAdmin(users, users[0]), isTrue);
      expect(AdminUserRules.isLastActiveAdmin(users, users[1]), isFalse,
          reason: 'a normal user is never the "last administrator"');
    });

    test('false once a second enabled administrator exists', () {
      final users = [
        user(id: '1', username: 'root', role: 'admin'),
        user(id: '2', username: 'ops', role: 'admin'),
      ];
      expect(AdminUserRules.isLastActiveAdmin(users, users[0]), isFalse);
    });

    test('a disabled administrator is not counted as cover', () {
      final users = [
        user(id: '1', username: 'root', role: 'admin'),
        user(id: '2', username: 'ops', role: 'admin', disabled: true),
      ];
      expect(AdminUserRules.isLastActiveAdmin(users, users[0]), isTrue);
    });

    test('does not name a row that is absent from the list', () {
      // Guards against a stale row captured before a refresh renaming ids.
      final users = [user(id: '1', username: 'root', role: 'admin')];
      expect(
        AdminUserRules.isLastActiveAdmin(
          users,
          user(id: 'gone', username: 'root', role: 'admin'),
        ),
        isFalse,
      );
    });
  });

  group('deletionBlocker', () {
    test('blocks deleting the signed-in account', () {
      final s = session(id: '1', username: 'root');
      final users = [
        user(id: '1', username: 'root', role: 'admin'),
        user(id: '2', username: 'ops', role: 'admin'),
      ];
      final reason = AdminUserRules.deletionBlocker(s, users, users[0]);
      expect(reason, isNotNull);
      expect(reason, contains('signed in'));
    });

    test('blocks deleting the last administrator and explains why', () {
      // Signed in as an ordinary user; only `root` is an administrator.
      final s = session(id: '9', username: 'ops');
      final users = [
        user(id: '1', username: 'root', role: 'admin'),
        user(id: '9', username: 'ops'),
      ];
      final reason = AdminUserRules.deletionBlocker(s, users, users[0]);
      expect(reason, isNotNull);
      expect(reason, contains('only administrator'));
      expect(reason, contains('Promote another account'));
    });

    test('allows deleting an ordinary account', () {
      final s = session(id: '1', username: 'root');
      final users = [
        user(id: '1', username: 'root', role: 'admin'),
        user(id: '2', username: 'grace'),
      ];
      expect(AdminUserRules.deletionBlocker(s, users, users[1]), isNull);
    });

    test('allows deleting a second administrator', () {
      final s = session(id: '1', username: 'root');
      final users = [
        user(id: '1', username: 'root', role: 'admin'),
        user(id: '2', username: 'ops', role: 'admin'),
      ];
      expect(AdminUserRules.deletionBlocker(s, users, users[1]), isNull);
    });
  });

  group('demotionBlocker', () {
    test('blocks blocking or demoting the last administrator', () {
      final s = session(id: '9', username: 'ops');
      final users = [
        user(id: '1', username: 'root', role: 'admin'),
        user(id: '9', username: 'ops'),
      ];
      expect(AdminUserRules.demotionBlocker(s, users, users[0]), isNotNull);
    });

    test('blocks blocking your own account', () {
      final s = session(id: '1', username: 'root');
      final users = [
        user(id: '1', username: 'root', role: 'admin'),
        user(id: '2', username: 'ops', role: 'admin'),
      ];
      expect(AdminUserRules.demotionBlocker(s, users, users[0]), isNotNull);
    });

    test('allows blocking an ordinary account', () {
      final s = session(id: '1', username: 'root');
      final users = [
        user(id: '1', username: 'root', role: 'admin'),
        user(id: '2', username: 'grace'),
      ];
      expect(AdminUserRules.demotionBlocker(s, users, users[1]), isNull);
    });
  });

  group('filter', () {
    final users = [
      user(id: '1', username: 'ada', displayName: 'Ada Lovelace', role: 'admin'),
      user(id: '2', username: 'grace', displayName: 'Grace Hopper'),
      user(id: '3', username: 'alex', displayName: 'Alex', disabled: true),
    ];

    test('empty query returns everyone', () {
      expect(AdminUserRules.filter(users, '   '), hasLength(3));
    });

    test('matches display name, username and role, case-insensitively', () {
      expect(AdminUserRules.filter(users, 'ada'), hasLength(1));
      expect(AdminUserRules.filter(users, 'GRACE'), hasLength(1));
      expect(AdminUserRules.filter(users, 'hopper'), hasLength(1));
      expect(AdminUserRules.filter(users, 'admin'), hasLength(1));
    });

    test('returns nothing when nothing matches', () {
      expect(AdminUserRules.filter(users, 'zzz'), isEmpty);
    });
  });
}
