import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../support/a11y.dart';

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
    for (final direction in TextDirection.values) {
      for (final swipe in [-1.0, 1.0]) {
        testWidgets('icon is revealed before label: $direction, swipe $swipe', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: ZenListItemActions(
                    showActionsLabel: 'Show',
                    hideActionsLabel: 'Hide',
                    actions: [
                      ZenListItemAction(icon: Icons.edit, label: 'Edit', onPressed: () {}),
                      ZenListItemAction(icon: Icons.delete, label: 'Delete', onPressed: () {}),
                    ],
                    child: const SizedBox(width: 600, height: 60, child: Text('Item')),
                  ),
                ),
              ),
            ),
          );
          final row = find.byType(Dismissible);
          final bounds = tester.getRect(row);
          final gesture = await tester.startGesture(bounds.center);
          await gesture.moveBy(Offset(40 * swipe, 0));
          await tester.pump();
          final first = (swipe > 0) == (direction == TextDirection.ltr);
          final icon = find.byIcon(first ? Icons.edit : Icons.delete);
          final label = find.text(first ? 'Edit' : 'Delete');
          final iconRect = tester.getRect(icon);
          final labelRect = tester.getRect(label);
          final moved = tester.getRect(find.text('Item'));
          if (swipe > 0) {
            expect(iconRect.left, lessThan(labelRect.left));
            expect(iconRect.left, lessThan(moved.left));
            expect(labelRect.left, greaterThan(moved.left));
          } else {
            expect(iconRect.right, greaterThan(labelRect.right));
            expect(iconRect.right, greaterThan(moved.right));
            expect(labelRect.right, lessThan(moved.right));
          }
          await gesture.up();
          await tester.pumpAndSettle();
        });
      }
    }

    for (final entry in auditThemes.entries) {
      testWidgets('swipe colors have contrast in ${entry.key}', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: Scaffold(
              body: ZenListItemActions(
                showActionsLabel: 'Show',
                hideActionsLabel: 'Hide',
                actions: [
                  ZenListItemAction(icon: Icons.edit, label: 'Edit', onPressed: () {}),
                  ZenListItemAction(
                    icon: Icons.delete,
                    label: 'Delete',
                    variant: ZenListItemActionVariant.destructive,
                    onPressed: () {},
                  ),
                ],
                child: const SizedBox(width: 600, height: 60, child: Text('Item')),
              ),
            ),
          ),
        );
        final scheme = entry.value.colorScheme;
        for (final swipe in [1.0, -1.0]) {
          final gesture = await tester.startGesture(tester.getCenter(find.byType(Dismissible)));
          await gesture.moveBy(Offset(200 * swipe, 0));
          await tester.pump();
          final label = find.text(swipe > 0 ? 'Edit' : 'Delete');
          final text = tester.widget<Text>(label);
          final bg = swipe > 0 ? scheme.primaryContainer : scheme.errorContainer;
          final fg = swipe > 0 ? scheme.onPrimaryContainer : scheme.onErrorContainer;
          expect(text.style!.color, fg);
          expect(tester.widget<Icon>(find.byIcon(swipe > 0 ? Icons.edit : Icons.delete)).color, fg);
          expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == bg), findsWidgets);
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
          await gesture.up();
          await tester.pumpAndSettle();
        }
      });
    }

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
