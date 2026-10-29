import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
    if (zenIsWeb) {
      expect(find.bySemanticsLabel('Edit'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Show actions'));
      await tester.pumpAndSettle();
    }
    if (zenIsMobile) {
      expect(find.bySemanticsLabel('Show actions'), findsNothing);
      final node = tester.getSemantics(find.text('Item'));
      final action = node.getSemanticsData().customSemanticsActionIds!.single;
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.customAction,
        action,
      );
      expect(calls, 1);
      semantics.dispose();
      return;
    }
    expect(find.bySemanticsLabel('Edit'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Edit'));
    expect(calls, 1);
    semantics.dispose();
  });

  if (zenIsMobile) {
    testWidgets('mobile swipes invoke the corresponding action', (tester) async {
      var edits = 0;
      var deletes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZenListItemActions(
              showActionsLabel: 'Show actions',
              hideActionsLabel: 'Hide actions',
              actions: [
                ZenListItemAction(icon: Icons.edit, label: 'Edit', onPressed: () => edits++),
                ZenListItemAction(icon: Icons.delete, label: 'Delete', onPressed: () => deletes++),
              ],
              child: const SizedBox(height: 60, child: Text('Item')),
            ),
          ),
        ),
      );
      expect(find.byType(Dismissible), findsOneWidget);
      await tester.drag(find.byType(Dismissible), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(edits, 1);
      expect(deletes, 0);
      expect(find.text('Item'), findsOneWidget);
      await tester.fling(find.byType(Dismissible), const Offset(-500, 0), 1200);
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(find.text('Item'), findsOneWidget);
    });

    testWidgets('RTL direction and disabled actions', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ZenListItemActions(
                showActionsLabel: 'Show',
                hideActionsLabel: 'Hide',
                actions: [
                  const ZenListItemAction(icon: Icons.edit, label: 'Edit', onPressed: null),
                  ZenListItemAction(icon: Icons.delete, label: 'Delete', onPressed: () => calls++),
                ],
                child: const SizedBox(width: 600, height: 60, child: Text('Item')),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(Dismissible), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.drag(find.byType(Dismissible), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(calls, 1);
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
