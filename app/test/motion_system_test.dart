import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_motion.dart';
import 'package:nexadrive/ui/widgets/nexa_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Focused checks for the central motion system. Screen-level transition tests
/// live next to their widgets; these cover the shared resolution rules.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AppMotion.resetMotionPreferenceForTesting);
  tearDown(AppMotion.resetMotionPreferenceForTesting);

  test('the app-level preference is persisted with SharedPreferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppMotion.setReduceAnimations(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppMotion.reduceAnimationsPreferenceKey), isTrue);

    AppMotion.appReduceAnimations.value = false;
    await AppMotion.loadReduceAnimationsPreference(prefs);
    expect(AppMotion.appReducedMotion, isTrue);
  });

  test('drag snapping uses velocity first, then the nearest edge', () {
    expect(
      AppMotion.resolveSnapTarget(
        current: 0.2,
        velocity: AppMotion.dragVelocityThreshold + 1,
        min: 0.0,
        max: 1.0,
      ),
      1.0,
    );
    expect(
      AppMotion.resolveSnapTarget(current: 0.4, velocity: 0, min: 0, max: 1),
      0.0,
    );
    expect(
      AppMotion.shouldDismissDrag(
        extent: 0.4,
        velocity: 0,
        totalExtent: 1,
      ),
      isTrue,
    );
  });

  testWidgets('app reduce shortens motion without suppressing information',
      (tester) async {
    await AppMotion.setReduceAnimations(true);
    late Duration full;
    late Duration stateChange;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            full = AppMotion.resolve(context, AppMotion.normal);
            stateChange =
                AppMotion.resolveStateChange(context, AppMotion.normal);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(full, Duration.zero);
    expect(stateChange, AppMotion.stateFade);
  });

  testWidgets('platform disableAnimations always wins', (tester) async {
    await AppMotion.setReduceAnimations(false);
    late Duration stateChange;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              stateChange =
                  AppMotion.resolveStateChange(context, AppMotion.normal);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(stateChange, Duration.zero);
  });

  testWidgets('flow reveal removes hidden content from the tree',
      (tester) async {
    Widget host(bool visible) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: NexaFlowReveal(
              visible: visible,
              child: const Text('Expanded section'),
            ),
          ),
        );

    await tester.pumpWidget(host(false));
    expect(find.text('Expanded section'), findsNothing);

    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(find.text('Expanded section'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
