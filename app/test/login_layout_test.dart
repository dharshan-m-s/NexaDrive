import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/login/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login remains usable on a short viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LoginScreen(session: Session()),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));

    await tester.enterText(fields.at(0), 'https://server.example.com');
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);

    await tester.enterText(fields.at(1), 'admin');
    await tester.enterText(fields.at(2), 'password');

    final signIn = find.text('Sign in');
    await tester.ensureVisible(signIn);
    await tester.pumpAndSettle();

    expect(signIn, findsOneWidget);
    expect(tester.getRect(signIn).bottom, lessThanOrEqualTo(640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving between login fields preserves focus', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LoginScreen(session: Session()),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.tap(fields.at(1));
    await tester.pump();
    expect(tester.binding.focusManager.primaryFocus, isNotNull);

    await tester.tap(fields.at(2));
    await tester.pump();
    expect(tester.binding.focusManager.primaryFocus, isNotNull);
    expect(
      tester.widget<EditableText>(
        find.descendant(
          of: fields.at(2),
          matching: find.byType(EditableText),
        ),
      ).focusNode.hasPrimaryFocus,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
