import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_app.dart';

/// Whether the lock screens are legible and named (WCAG 1.4.3 Contrast, 1.4.4 Resize Text,
/// 2.5.8 Target Size, 4.1.2 Name, Role, Value). They are built from zen_ui_widgets controls,
/// whose own suites cover each idiom; this checks the screens assembled from them.
void main() {
  final themes = <String, ThemeData>{
    for (final brightness in Brightness.values)
      brightness.name: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
      ),
  };

  for (final entry in themes.entries) {
    testWidgets('the unlock screen meets AA contrast and target size (${entry.key})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final lock = await memoryLock(pin: '2468');

      await tester.pumpWidget(lockedApp(lock: lock, theme: entry.value));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  }

  testWidgets('the PIN field is named once and every button by its label', (tester) async {
    final handle = tester.ensureSemantics();
    final lock = await memoryLock(pin: '2468');

    await tester.pumpWidget(lockedApp(lock: lock));

    final field = tester.getSemantics(find.byType(EditableText));
    expect(RegExp('PIN').allMatches(field.label), hasLength(1), reason: field.label);
    expect(find.bySemanticsLabel('Unlock'), findsOneWidget);
    expect(find.bySemanticsLabel('Forgot PIN?'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the unlock screen lays out at 200% text', (tester) async {
    final lock = await memoryLock(pin: '2468');
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: lockedApp(lock: lock),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Unlock'), findsOneWidget);
  });
}
