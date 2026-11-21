import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_dimensions.dart';
import 'package:nexadrive/ui/widgets/nexa_pill_notice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpNotice(
    WidgetTester tester,
    NexaPillNotice notice, {
    bool reducedMotion = false,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppDimens.bottomNavMaxWidth,
              ),
              child: notice,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an unattended notice auto-dismisses', (tester) async {
    var dismissals = 0;
    await pumpNotice(
      tester,
      NexaPillNotice(
        message: 'Queued for upload',
        onDismissed: () => dismissals++,
      ),
    );
    expect(find.text('Queued for upload'), findsOneWidget);

    await tester.pump(NexaPillNotice.autoDismissDelay);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Queued for upload'), findsNothing);
    expect(dismissals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a notice action runs once and dismisses the pill',
      (tester) async {
    var actions = 0;
    var dismissals = 0;
    await pumpNotice(
      tester,
      NexaPillNotice(
        message: 'That upload didn’t finish',
        actionLabel: 'Retry',
        onAction: () => actions++,
        onDismissed: () => dismissals++,
      ),
    );

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(actions, 1);
    expect(dismissals, 1);
    expect(find.text('That upload didn’t finish'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a horizontal swipe dismisses early', (tester) async {
    var dismissals = 0;
    await pumpNotice(
      tester,
      NexaPillNotice(
        message: 'Sync needs attention',
        onDismissed: () => dismissals++,
      ),
    );

    await tester.drag(find.byType(NexaPillNotice), const Offset(160, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(dismissals, 1);
    expect(find.text('Sync needs attention'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a downward swipe dismisses early with reduced motion',
      (tester) async {
    var dismissals = 0;
    await pumpNotice(
      tester,
      NexaPillNotice(
        message: 'The server restarted',
        onDismissed: () => dismissals++,
      ),
      reducedMotion: true,
    );

    await tester.drag(find.byType(NexaPillNotice), const Offset(0, 80));
    await tester.pumpAndSettle();

    expect(dismissals, 1);
    expect(find.text('The server restarted'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
