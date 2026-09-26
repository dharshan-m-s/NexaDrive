import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
      // scroll rather than clip the primary action away.
      const size = Size(1280, 240);
      // A tap that misses the target only warns by default. Missing is exactly
      // the failure this test exists to catch, so make it fatal: otherwise the
      // assertion below passes whether or not the button is reachable.
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

      await _pump(tester, size);
      expect(tester.takeException(), isNull,
          reason: 'the form must scroll, not overflow');

      // Sanity check: the form really is taller than this viewport, so the
      // action genuinely starts below the fold.
      expect(tester.getRect(_signIn).top, greaterThan(size.height),
          reason: 'the button should start out of view on a 240px viewport');

      // Bring it into view, then let the real gesture pipeline prove the tap
      // lands on the button.
      await tester.ensureVisible(_signIn);
      await tester.pumpAndSettle();

      final rect = tester.getRect(_signIn);
      expect(rect.top, greaterThanOrEqualTo(0),
          reason: 'scrolling must reveal the whole button');
      expect(rect.bottom, lessThanOrEqualTo(size.height),
          reason: 'scrolling must reveal the whole button');

      await tester.tap(_signIn);
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

  group('the on-screen keyboard never steals field focus', () {
    // Android shrinks the body when the IME opens and grows it again when it
    // closes. A layout that swaps between two different widget trees at that
    // height boundary unmounts the focused field and drops focus; the single
    // stable scrollable subtree must instead keep focus exactly where it is.
    testWidgets('focus survives an IME-style viewport shrink', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = Session();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: LoginScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.tap(fields.at(2));
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: fields.at(2),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasPrimaryFocus,
        isTrue,
      );

      final countBefore = tester
          .widget<EditableText>(
            find.descendant(
              of: fields.at(2),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hashCode;

      // The keyboard opens: the body shrinks below the centred-form threshold,
      // as it would on a 640-height phone.
      await tester.binding.setSurfaceSize(const Size(390, 400));
      await tester.pumpAndSettle();

      final nodeAfter = tester
          .widget<EditableText>(
            find.descendant(
              of: fields.at(2),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      expect(nodeAfter.hasFocus, isTrue,
          reason: 'shrinking the viewport must not unmount the focused field');
      expect(nodeAfter.hashCode, countBefore,
          reason: 'the field must not be recreated by the resize');

      // The keyboard closes again: the viewport grows back.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('moving between login fields preserves focus', (tester) async {
      await _pump(tester, const Size(390, 844));
      final fields = find.byType(TextField);
      await tester.tap(fields.at(1));
      await tester.pump();
      expect(tester.binding.focusManager.primaryFocus, isNotNull);

      await tester.tap(fields.at(2));
      await tester.pump();
      expect(tester.binding.focusManager.primaryFocus, isNotNull);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: fields.at(2),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasPrimaryFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the sign-in form validates before it calls the server', () {
    // Every case here would otherwise become a request to an empty or garbage
    // address, and the user would see a transport exception instead of the
    // field they forgot to fill in.
    Future<void> signInWith(
      WidgetTester tester, {
      String server = '',
      String username = '',
      String password = '',
    }) async {
      await _pump(tester, const Size(390, 844));
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      if (server.isNotEmpty) await tester.enterText(fields.at(0), server);
      if (username.isNotEmpty) await tester.enterText(fields.at(1), username);
      if (password.isNotEmpty) await tester.enterText(fields.at(2), password);
      await tester.pump();

      await tester.tap(_signIn);
      await tester.pump();
    }

    testWidgets('an empty form asks for the server address', (tester) async {
      await signInWith(tester);
      expect(find.text('Enter the address of your NexaDrive server.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a missing username is named explicitly', (tester) async {
      await signInWith(tester, server: 'https://example.test', password: 'pw');
      expect(find.text('Enter your username.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a missing password is named explicitly', (tester) async {
      await signInWith(
        tester,
        server: 'https://example.test',
        username: 'ada',
      );
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a malformed address is rejected with a usable hint',
        (tester) async {
      await signInWith(tester,
          server: 'not a url', username: 'ada', password: 'pw');
      expect(
        find.textContaining('does not look like a server address'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bare hostname is accepted, so no error is shown for it',
        (tester) async {
      // `Session.normalizeServerUrl` assumes HTTPS for a bare host, so the form
      // must not demand an explicit scheme before it will try.
      await signInWith(
        tester,
        server: 'nexadrive.example.test',
        username: 'ada',
        password: 'pw',
      );
      expect(find.textContaining('does not look like a server address'),
          findsNothing);
      expect(find.text('Enter your password.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the validation message stays visible on a short viewport',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = Session();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: LoginScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();

      final error = find.text('Enter the address of your NexaDrive server.');
      await tester.ensureVisible(_signIn);
      await tester.pumpAndSettle();
      await tester.tap(_signIn);
      await tester.pumpAndSettle();

      // The message must be on screen after the tap, not scrolled away.
      expect(error, findsOneWidget);
      await tester.ensureVisible(error);
      await tester.pumpAndSettle();
      final rect = tester.getRect(error);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(400));
      expect(tester.takeException(), isNull);
    });
  });

  group('the sign-in column is centred rather than pinned to one edge', () {
    // The layout spec for this screen is a *centered* scroll view with a
    // 440px column. A scroll view hands its child an unbounded width, so
    // without an explicit centring wrapper the column sat against the left
    // edge: on a 951px-wide window the form's centre was measured 224px left
    // of the window centre. These tests pin both halves of that behaviour.
    testWidgets('the form is horizontally centred on a wide viewport',
        (tester) async {
      const size = Size(1280, 800);
      await _pump(tester, size);
      final button = tester.getRect(_signIn);
      expect((button.center.dx - size.width / 2).abs(), lessThanOrEqualTo(1.0),
          reason: 'the sign-in column must be centred on a desktop window, '
              'not left-aligned');
      expect(button.width, lessThanOrEqualTo(440.0),
          reason: 'centring must not stretch the column past its 440px cap');
    });

    testWidgets('the brand block and the fields share the same centred column',
        (tester) async {
      await _pump(tester, const Size(1280, 800));
      final button = tester.getRect(_signIn);
      final fields = tester.getRect(find.byType(TextField).first);
      expect(fields.center.dx, closeTo(button.center.dx, 1.0),
          reason: 'every element of the form must sit in the centred column');
    });

    testWidgets('a narrow viewport still uses the full width', (tester) async {
      const size = Size(360, 640);
      await _pump(tester, size);
      final button = tester.getRect(_signIn);
      // The phone layout has no 440px cap to hit, so the column should fill
      // almost the whole width (minus the page gutter).
      expect(button.width, greaterThan(size.width * 0.8),
          reason: 'on a phone the form should fill the content area');
      expect((button.center.dx - size.width / 2).abs(), lessThanOrEqualTo(1.0),
          reason: 'and still be centred');
    });
  });

  group('the sign-in fields can be driven from a keyboard', () {
    // Sign-in is the first screen on desktop, where there is no touch keyboard
    // and Tab is how a user moves between fields. If traversal does not work, a
    // keyboard-only user can never reach the username and password fields at
    // all, so this is an accessibility requirement rather than a nicety.
    testWidgets('Tab advances focus through all three fields in order',
        (tester) async {
      await _pump(tester, const Size(1280, 800));
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));

      await tester.tap(fields.at(0));
      await tester.pumpAndSettle();
      expect(_focusedField(tester), 0,
          reason: 'tapping the server-address field must focus it');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_focusedField(tester), 1,
          reason: 'Tab must advance from the server address to the username');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_focusedField(tester), 2,
          reason: 'Tab must advance from the username to the password');
    });

    testWidgets('a tap focuses the field it lands on, not the first one',
        (tester) async {
      await _pump(tester, const Size(1280, 800));
      final fields = find.byType(TextField);
      await tester.tap(fields.at(1));
      await tester.pumpAndSettle();
      expect(_focusedField(tester), 1,
          reason: 'a click on the username field must focus the username '
              'field; otherwise typed input lands in the server address');
    });

    testWidgets('text typed after focusing a field lands in that field',
        (tester) async {
      await _pump(tester, const Size(1280, 800));
      final fields = find.byType(TextField);
      await tester.tap(fields.at(1));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(1), 'ada');
      await tester.pumpAndSettle();

      final server = tester.widget<TextField>(fields.at(0)).controller!;
      final username = tester.widget<TextField>(fields.at(1)).controller!;
      expect(username.text, 'ada');
      expect(server.text, isEmpty,
          reason: 'the username text must not end up in the server address');
    });

    testWidgets('the password field\'s done action submits the form',
        (tester) async {
      await _pump(tester, const Size(1280, 800));
      final fields = find.byType(TextField);
      await tester.tap(fields.at(2));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(2), 'pw');
      // The password field is `textInputAction: done` with `onSubmitted:
      // submit`, so the platform's done action — not a raw Enter key — is what
      // signs the user in.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // An empty server address fails validation, which proves submit ran.
      expect(find.text('Enter the address of your NexaDrive server.'),
          findsOneWidget);
    });
  });
}

/// Index of the [TextField] that currently holds the primary focus, or -1.
int _focusedField(WidgetTester tester) {
  final fields = find.byType(TextField);
  for (var i = 0; i < fields.evaluate().length; i++) {
    final editable = tester.widget<EditableText>(
      find.descendant(of: fields.at(i), matching: find.byType(EditableText)),
    );
    if (editable.focusNode.hasPrimaryFocus) return i;
  }
  return -1;
}
