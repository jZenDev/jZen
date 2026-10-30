import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

void main() {
  testWidgets('centers configurable widths and keeps a gutter on narrow windows', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> show(double width, double maximum) async {
      tester.view.physicalSize = Size(width, 600);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZenContentWidth(
              maxWidth: maximum,
              gutter: 20,
              child: const SizedBox(key: ValueKey('content'), height: 50),
            ),
          ),
        ),
      );
    }

    await show(1200, 700);
    expect(
      tester.getRect(find.byKey(const ValueKey('content'))),
      const Rect.fromLTWH(250, 0, 700, 50),
    );
    await show(1200, 900);
    expect(tester.getSize(find.byKey(const ValueKey('content'))).width, 900);
    await show(400, 700);
    expect(
      tester.getRect(find.byKey(const ValueKey('content'))),
      const Rect.fromLTWH(20, 0, 360, 50),
    );
  });

  testWidgets('host measures its full width and detail measures its pane or pushed page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> show(double width) async {
      tester.view.physicalSize = Size(width, 600);
      await tester.pumpWidget(
        MaterialApp(
          home: ZenDetailHost(
            child: ZenContentWidth(
              maxWidth: 500,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showZenDetail<void>(
                    context,
                    builder: (_) => const Scaffold(
                      body: ZenContentWidth(
                        maxWidth: 500,
                        child: SizedBox(key: ValueKey('detail-content'), height: 50),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    await show(1000);
    expect(find.text('Open'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('detail-content'))).width, 368);
    await tester.pumpWidget(const SizedBox());
    await show(500);
    expect(tester.getSize(find.byKey(const ValueKey('detail-content'))).width, 468);
  });
}
