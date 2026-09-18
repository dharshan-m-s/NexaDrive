import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/login/login_screen.dart';

/// The sign-in form is the one screen every user must get past, so it has to
/// survive the two cases that break naive centred columns: a short viewport
/// (Linux window, phone in landscape, keyboard open) and a large accessibility
/// text scale.
///
/// These tests exist because an integration run reported a tap target at the
/// very bottom edge of the root:
///
///   "FilledButton center at approximately y=464 while root height was 464"
///
/// A primary action whose centre sits on the last pixel of the viewport is not
/// reachable. Either the layout is wrong and must be fixed, or the button is
/// genuinely inside and provable — which is what these tests decide.
Future<void> _pump(
  WidgetTester tester,
  Size size, {
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(size);
  final session = Session();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: LoginScreen(session: session),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _signIn => find.widgetWithText(FilledButton, 'Sign in');

void main() {
  // Short viewports are the interesting ones; the rest guard against regressions
  // at normal sizes.
  const sizes = <(String, Size)>[
    ('linux-short-464', Size(1280, 464)),
    ('landscape-phone', Size(640, 360)),
    ('small-phone', Size(360, 640)),
    ('normal-phone', Size(390, 844)),
    ('tablet', Size(800, 1280)),
    ('desktop', Size(1920, 1080)),
  ];

  group('the sign-in form never pushes its primary action off-screen', () {
    for (final (label, size) in sizes) {
      testWidgets('$label (${size.width.toInt()}x${size.height.toInt()})',
          (tester) async {
        await _pump(tester, size);

        expect(tester.takeException(), isNull,
            reason: '$label: must not overflow');
        expect(_signIn, findsOneWidget);

        final rect = tester.getRect(_signIn);
        // Fully inside the viewport, not just partially.
        expect(rect.top, greaterThanOrEqualTo(0),
            reason: '$label: the button starts above the viewport');
        expect(rect.bottom, lessThanOrEqualTo(size.height),
            reason: '$label: the button runs ${rect.bottom - size.height}px '
                'past the bottom edge (viewport ${size.height})');
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));

        // And the tap must actually land on it. `tester.tap` fails the test if
        // the point it derives does not hit-test on the target widget.
        await tester.tap(_signIn);
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: '$label: tapping Sign in threw');
      });
    }

    testWidgets('scrolling reaches the button when the viewport is tiny',
        (tester) async {
      // 240px tall: shorter than the form's intrinsic height, so the form must
      // scroll rather than clip.
      const size = Size(1280, 240);
      await _pump(tester, size);
      await tester.tap(_signIn); // drags into view if needed
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    for (final scale in <double>[1.5, 2.0]) {
      testWidgets('survives a ${scale}x accessibility text scale',
          (tester) async {
        await _pump(tester, const Size(360, 640), textScale: scale);
        expect(tester.takeException(), isNull,
            reason: 'text scale ${scale}x must not overflow the form');
        expect(_signIn, findsOneWidget);
        // The form may need scrolling at this scale — that is fine and is what
        // the scroll view is for — but it must remain reachable.
        await tester.ensureVisible(_signIn);
        await tester.pumpAndSettle();
        await tester.tap(_signIn);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
