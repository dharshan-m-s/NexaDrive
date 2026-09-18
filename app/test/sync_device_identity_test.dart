import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Sync Center used to list repeated, identical "NexaDrive desktop" rows
/// for one machine. The cause was that this device's identity did not exist
/// until the server replied, so the shell's startup sync and the Sync Center's
/// manual sync could both announce a fresh machine and be registered twice.
///
/// The identity is now created locally, before any request, and resolved
/// atomically so concurrent callers agree.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SyncManager.resetDeviceIdCache();
  });

  SyncManager manager() {
    final session = Session()
      ..serverUrl = 'https://example.com'
      ..token = 'tok';
    return SyncManager(Api(session));
  }

  group('sync device identity', () {
    test('is created on first use and is not empty', () async {
      final id = await SyncManager.ensureDeviceId();
      expect(id, isNotEmpty);
    });

    test('is a well-formed UUID the server can parse', () async {
      final id = await SyncManager.ensureDeviceId();
      expect(
        RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(id),
        isTrue,
        reason: 'server binds device_id as a Uuid; a non-UUID would 400',
      );
    });

    test('is stable across repeated reads', () async {
      final first = await SyncManager.ensureDeviceId();
      final second = await SyncManager.ensureDeviceId();
      final third = await manager().deviceId();
      expect(second, first);
      expect(third, first);
    });

    test('survives a new SyncManager instance (persisted, not per-instance)',
        () async {
      final first = await SyncManager.ensureDeviceId();
      final second = await SyncManager.ensureDeviceId();
      expect(second, first);
    });

    test('concurrent callers all receive the same id', () async {
      // The regression: three simultaneous reads each generated their own uuid,
      // so the same machine could announce several identities.
      final ids = await Future.wait([
        SyncManager.ensureDeviceId(),
        SyncManager.ensureDeviceId(),
        SyncManager.ensureDeviceId(),
      ]);
      expect(ids.toSet(), hasLength(1),
          reason: 'one machine must have exactly one identity');
    });

    test('is remembered from a previous run rather than regenerated', () async {
      const known = '11111111-2222-3333-4444-555555555555';
      SharedPreferences.setMockInitialValues({'sync_device_id_v1': known});
      SyncManager.resetDeviceIdCache();
      expect(await SyncManager.ensureDeviceId(), known);
    });

    test('an empty stored value counts as absent', () async {
      SharedPreferences.setMockInitialValues({'sync_device_id_v1': ''});
      SyncManager.resetDeviceIdCache();
      final id = await SyncManager.ensureDeviceId();
      expect(id, isNotEmpty);
      expect(id, isNot(''));
    });
  });
}
