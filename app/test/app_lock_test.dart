import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/services/app_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prompt counter shared by the stub; read per test after resetting.
int _promptCount = 0;

/// Stub service: counts authentication rounds so double-prompt races are
/// visible as numbers.
class _StubService extends AppLockService {
  _StubService({
    required AppLockResult result,
    bool canAuthenticate = true,
  }) : super(
          authenticateWithDevice: () {
            // A top-level counter, because an initializer closure cannot
            // touch instance state.
            _promptCount++;
            return Future.value(result);
          },
          canAuthenticateOnDevice: () async => canAuthenticate,
        );
}

/// A service whose only working part is the preference round-trip.
class _PrefsService extends AppLockService {
  _PrefsService(bool can)
      : super(
          authenticateWithDevice: () async => AppLockResult.unlocked,
          canAuthenticateOnDevice: () async => can,
        );
}

void main() {
  group('AppLockService preference contract', () {
    test('starts disabled', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _PrefsService(true);
      expect(await service.isEnabled(), isFalse);
    });

    test('round-trips on/off', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _PrefsService(true);
      expect(await service.setEnabled(true), isTrue);
      expect(await service.isEnabled(), isTrue);
      await service.setEnabled(false);
      expect(await service.isEnabled(), isFalse);
    });

    test('cannot be enabled without a device credential', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _PrefsService(false);
      expect(await service.setEnabled(true), isFalse,
          reason: 'a device with no screen lock must not pretend to lock');
      expect(await service.isEnabled(), isFalse);
    });

    test('can always be turned off', () async {
      SharedPreferences.setMockInitialValues({});
      final service = _PrefsService(false);
      await service.setEnabled(true);
      expect(await service.setEnabled(false), isTrue);
      expect(await service.isEnabled(), isFalse);
    });
  });

  group('AppLockGate', () {
    testWidgets('renders the child untouched when App Lock is off',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      _promptCount = 0;
      final service = _StubService(result: AppLockResult.unlocked);
      await tester.pumpWidget(
        MaterialApp(
            home: AppLockGate(service: service, child: const Text('app'))),
      );
      await tester.pump();
      expect(find.text('app'), findsOneWidget);
      expect(find.text('NexaDrive is locked'), findsNothing);
      expect(_promptCount, 0, reason: 'a disabled lock must never prompt');
    });

    testWidgets('locks and prompts once when enabled at startup',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      _promptCount = 0;
      final service = _StubService(result: AppLockResult.unlocked);
      await service.setEnabled(true);

      await tester.pumpWidget(
        MaterialApp(
            home: AppLockGate(service: service, child: const Text('app'))),
      );
      await tester.pump();
      // The stub answers immediately, so the resolved (unlocked) state is the
      // steady state on a cold start; what the test pins is that the gate
      // asked exactly once and hid content *while* the prompt was open.
      await tester.pumpAndSettle();

      expect(_promptCount, 1, reason: 'exactly one prompt for a cold start');
      expect(find.text('app'), findsOneWidget);
    });

    testWidgets('a slow prompt keeps content hidden until it resolves',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      _promptCount = 0;
      final completer = Completer<AppLockResult>();
      final service = AppLockService(
        authenticateWithDevice: () => completer.future,
        canAuthenticateOnDevice: () async => true,
      );
      await service.setEnabled(true);

      await tester.pumpWidget(
        MaterialApp(
            home: AppLockGate(service: service, child: const Text('app'))),
      );
      await tester.pump();

      // While the device prompt is open, nothing of the app is mounted.
      expect(find.text('NexaDrive is locked'), findsOneWidget);
      expect(find.text('app'), findsNothing);

      completer.complete(AppLockResult.unlocked);
      await tester.pumpAndSettle();
      expect(find.text('app'), findsOneWidget);
    });

    testWidgets('a cancelled attempt keeps the gate up and offers retry',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      _promptCount = 0;
      final service = _StubService(result: AppLockResult.cancelled);
      await service.setEnabled(true);

      await tester.pumpWidget(
        MaterialApp(
            home: AppLockGate(service: service, child: const Text('app'))),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('NexaDrive is locked'), findsOneWidget);
      expect(find.text('app'), findsNothing);

      // The retry button exists and re-prompts.
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      expect(_promptCount, 2);
      expect(find.text('NexaDrive is locked'), findsOneWidget);
    });

    testWidgets('an unlocked attempt reveals the app', (tester) async {
      SharedPreferences.setMockInitialValues({});
      _promptCount = 0;
      final service = _StubService(result: AppLockResult.unlocked);
      await service.setEnabled(true);

      await tester.pumpWidget(
        MaterialApp(
            home: AppLockGate(service: service, child: const Text('app'))),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('app'), findsOneWidget);
      expect(find.text('NexaDrive is locked'), findsNothing);
    });

    testWidgets('a missing device credential fails open with an explanation',
        (tester) async {
      // The device lost its screen lock while App Lock was on. Keeping the
      // gate up would make the app permanently unusable, so the gate fails
      // open instead of bricking the session.
      SharedPreferences.setMockInitialValues({});
      _promptCount = 0;
      final service = _StubService(
        result: AppLockResult.noDeviceCredential,
      );
      await service.setEnabled(true);

      await tester.pumpWidget(
        MaterialApp(
            home: AppLockGate(service: service, child: const Text('app'))),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('app'), findsOneWidget,
          reason:
              'the gate must fail open when the device cannot authenticate');
      expect(
        find.textContaining('no screen lock'),
        findsOneWidget,
        reason: 'the fail-open must be explained, not silent',
      );
    });
  });
}
