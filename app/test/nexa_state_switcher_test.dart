import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/ui/widgets/nexa_loading_state.dart';

/// Behavioural checks for [NexaStateSwitcher], the cross-fade used between a
/// page's loading, empty, error and content states.
void main() {
  Widget host(Key stateKey, String label, {bool reducedMotion = false}) {
    final app = MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: NexaStateSwitcher(
          stateKey: stateKey,
          child: Center(child: Text(label)),
        ),
      ),
    );
    if (!reducedMotion) return app;
    return MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: app,
    );
  }

  testWidgets('renders the current state without touching the screen',
      (tester) async {
    await tester.pumpWidget(host(const ValueKey('loading'), 'Loading'));
    expect(find.text('Loading'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cross-fades when the state changes', (tester) async {
    await tester.pumpWidget(host(const ValueKey('loading'), 'Loading'));

    await tester.pumpWidget(host(const ValueKey('content'), 'Content'));
    // Mid-transition the outgoing and incoming states share the screen, so the
    // change reads as a settle rather than a swap.
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.text('Loading'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);

    // Once settled, only the new state remains.
    await tester.pumpAndSettle();
    expect(find.text('Loading'), findsNothing);
    expect(find.text('Content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swaps in place when only the content changes', (tester) async {
    await tester.pumpWidget(host(const ValueKey('content'), 'First'));

    // Same state key: the body updates without replaying the fade.
    await tester.pumpWidget(host(const ValueKey('content'), 'Second'));
    await tester.pump();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('reduced motion swaps instantly, leaving nothing behind',
      (tester) async {
    await tester.pumpWidget(
      host(const ValueKey('loading'), 'Loading', reducedMotion: true),
    );

    await tester.pumpWidget(
      host(const ValueKey('content'), 'Content', reducedMotion: true),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Loading'), findsNothing);
    expect(find.text('Content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
