import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

void main() {
  testWidgets('actions are available with the platform interaction', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZenListItemActions(
            showActionsLabel: 'Show actions',
            hideActionsLabel: 'Hide actions',
            actions: [ZenListItemAction(icon: Icons.edit, label: 'Edit', onPressed: () => calls++)],
            child: const Text('Item'),
          ),
        ),
      ),
    );
    final semantics = tester.ensureSemantics();
    if (!zenIsDesktop) {
      expect(find.bySemanticsLabel('Edit'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Show actions'));
      await tester.pumpAndSettle();
    }
    expect(find.bySemanticsLabel('Edit'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Edit'));
    expect(calls, 1);
    semantics.dispose();
  });

  if (zenIsMobile) {
    testWidgets('swiping opens actions without invoking them', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZenListItemActions(
              showActionsLabel: 'Show actions',
              hideActionsLabel: 'Hide actions',
              actions: [
                ZenListItemAction(icon: Icons.edit, label: 'Edit', onPressed: () => calls++),
              ],
              child: const SizedBox(height: 60, child: Text('Item')),
            ),
          ),
        ),
      );
      await tester.fling(find.text('Item'), const Offset(-200, 0), 1000);
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Edit'), findsOneWidget);
      expect(calls, 0);
      semantics.dispose();
    });
  }

  if (zenIsWeb) {
    testWidgets('keyboard focus reveals actions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZenListItemActions(
              showActionsLabel: 'Show actions',
              hideActionsLabel: 'Hide actions',
              actions: [ZenListItemAction(icon: Icons.edit, label: 'Edit', onPressed: () {})],
              child: const Text('Item'),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Edit'), findsOneWidget);
      semantics.dispose();
    });
  }
}
