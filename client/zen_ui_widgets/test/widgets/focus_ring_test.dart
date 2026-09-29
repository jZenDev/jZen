import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../support/a11y.dart';

/// The ring follows CSS `:focus-visible`: shown after a key press or with assistive technology
/// attached, hidden after any pointer press (WCAG 2.4.7, 1.4.11).
void main() {
  Widget button(VoidCallback onPressed) => FocusRing.wrapping(
    child: FilledButton(onPressed: onPressed, child: const Text('Go')),
  );

  testWidgets('wrapping a control does not take its focus, size or constraints', (tester) async {
    await pumpApp(tester, button(() {}), size: const Size(300, 600));
    final Size wrapped = tester.getSize(find.byType(FilledButton));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FilledButton(onPressed: null, child: Text('Go'))),
      ),
    );
    expect(wrapped.height, tester.getSize(find.byType(FilledButton)).height);
  });

  testWidgets('a ring appears with the key press and the control keeps focus through it', (
    tester,
  ) async {
    int taps = 0;
    await pumpApp(tester, button(() => taps++));
    expect(isRinged(tester, find.byType(FocusRing)), isFalse);

    await press(tester, LogicalKeyboardKey.tab);
    expect(isRinged(tester, find.byType(FocusRing)), isTrue);
    await press(tester, LogicalKeyboardKey.enter);
    expect(taps, 1, reason: 'the ring did not remount the button and drop its focus');
  }, semanticsEnabled: false);

  for (final PointerDeviceKind kind in <PointerDeviceKind>[
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
  ]) {
    testWidgets('a ${kind.name} press hides the ring', (tester) async {
      await pumpApp(tester, button(() {}));
      await press(tester, LogicalKeyboardKey.tab);
      expect(isRinged(tester, find.byType(FocusRing)), isTrue);
      await tester.tap(find.text('Go'), kind: kind);
      await tester.pumpAndSettle();
      expect(isRinged(tester, find.byType(FocusRing)), isFalse);
    }, semanticsEnabled: false);
  }

  testWidgets('with assistive technology attached the ring stays despite a click', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(tester, button(() {}));
    await press(tester, LogicalKeyboardKey.tab);
    await tester.tap(find.text('Go'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(isRinged(tester, find.byType(FocusRing)), isTrue);
    handle.dispose();
  });

  for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
    testWidgets('the ring stands 3:1 off the surface (${theme.key})', (tester) async {
      final ColorScheme scheme = theme.value.colorScheme;
      expect(contrastRatio(scheme.primary, scheme.surface), greaterThanOrEqualTo(3));
    });
  }
}
