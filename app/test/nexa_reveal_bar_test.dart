import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/ui/widgets/nexa_action_bar.dart';

/// Behavioural checks for [NexaRevealBar], the slide-up reveal used for the
/// selection action bar.
void main() {
  Widget host(bool visible, {bool reducedMotion = false}) {
    final app = MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox()),
            NexaRevealBar(
              visible: visible,
              child: const SizedBox(height: 60, child: Text('Action bar')),
            ),
          ],
        ),
      ),
    );
    if (!reducedMotion) return app;
    return MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: app,
    );
  }

  testWidgets('hides the bar until it is revealed', (tester) async {
    await tester.pumpWidget(host(false));
    expect(find.text('Action bar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slides the bar in when revealed', (tester) async {
    await tester.pumpWidget(host(false));
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(find.text('Action bar'), findsOneWidget);

    // Leaving selection removes it again.
    await tester.pumpWidget(host(false));
    await tester.pumpAndSettle();
    expect(find.text('Action bar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows the bar without animating', (tester) async {
    await tester.pumpWidget(host(false, reducedMotion: true));
    await tester.pumpWidget(host(true, reducedMotion: true));
    await tester.pump();
    expect(find.text('Action bar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
