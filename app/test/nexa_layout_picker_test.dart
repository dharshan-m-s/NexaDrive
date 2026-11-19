import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/ui/widgets/nexa_layout_picker.dart';

void main() {
  testWidgets('layout picker uses a 1-8 density slider', (tester) async {
    int? chosen;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                chosen = await showNexaGridLayoutPicker(
                  context: tester.element(find.byType(ElevatedButton)),
                  columns: 3,
                  title: 'Gallery layout',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Fewer'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('1 column'), findsNothing);
    expect(find.text('2 columns'), findsNothing);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(chosen, 3);
  });
}
