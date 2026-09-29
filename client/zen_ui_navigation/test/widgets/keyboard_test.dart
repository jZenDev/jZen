import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_desktop.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_focus.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_web.dart';

import '../support/a11y.dart';

/// Keyboard-only use of the desktop and web navigation (WCAG 2.1.1 Keyboard, 2.4.3 Focus Order,
/// 2.4.7 Focus Visible, 1.4.11 Non-text Contrast). Every destination must be reachable with Tab
/// and the arrow keys, activate with Enter and Space, and show a ring a sighted keyboard user can
/// see — and the ring must not appear for a pointer user.

/// Indices of the destinations currently drawing a focus ring.
List<int> ringed(WidgetTester tester) {
  final rings = find.byType(FocusRing).evaluate().toList();
  return <int>[
    for (int i = 0; i < rings.length; i++)
      if (find
          .descendant(
            of: find.byElementPredicate((e) => identical(e, rings[i])),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).border != null,
            ),
          )
          .evaluate()
          .isNotEmpty)
        i,
  ];
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  group('Desktop NavigationRail', () {
    testWidgets('Tab, arrows, Enter and Space reach and activate every destination', (
      tester,
    ) async {
      final selections = <int>[];
      await pumpNavigation(
        tester,
        (ctx) => buildDesktopNavigation(
          context: ctx,
          selectedIndex: 0,
          onItemSelected: selections.add,
          items: auditItems(),
        ),
      );
      expect(ringed(tester), isEmpty, reason: 'nothing is focused before the first key');

      await press(tester, LogicalKeyboardKey.tab);
      expect(ringed(tester), <int>[0]);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(ringed(tester), <int>[1]);
      await press(tester, LogicalKeyboardKey.enter);
      expect(selections, <int>[1]);

      await press(tester, LogicalKeyboardKey.tab);
      expect(ringed(tester), <int>[2]);
      await press(tester, LogicalKeyboardKey.space);
      expect(selections, <int>[1, 2]);

      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(ringed(tester), <int>[1]);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(ringed(tester), <int>[0]);
    });

    testWidgets('a pointer tap draws no focus ring', (tester) async {
      await pumpNavigation(
        tester,
        (ctx) => buildDesktopNavigation(
          context: ctx,
          selectedIndex: 0,
          onItemSelected: (_) {},
          items: auditItems(),
        ),
      );
      await press(tester, LogicalKeyboardKey.tab);
      expect(ringed(tester), <int>[0]);

      await tester.tap(find.text('Item 1'));
      await tester.pumpAndSettle();
      expect(ringed(tester), isEmpty);
    });
  });

  group('Web top menu', () {
    testWidgets('Tab, arrows and Enter reach and activate every destination', (tester) async {
      final selections = <int>[];
      await pumpNavigation(
        tester,
        (ctx) => buildPlatformNavigation(
          context: ctx,
          selectedIndex: 0,
          onItemSelected: selections.add,
          items: auditItems(),
        ),
      );

      await press(tester, LogicalKeyboardKey.tab);
      expect(ringed(tester), <int>[0]);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(ringed(tester), <int>[1]);
      await press(tester, LogicalKeyboardKey.enter);
      expect(selections, <int>[1]);
      await press(tester, LogicalKeyboardKey.tab);
      expect(ringed(tester), <int>[2]);
      await press(tester, LogicalKeyboardKey.space);
      expect(selections, <int>[1, 2]);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(ringed(tester), <int>[1]);
    });

    testWidgets('at 200% text every destination is still reachable and nothing overflows', (
      tester,
    ) async {
      const count = 8;
      await pumpNavigation(
        tester,
        (ctx) => buildPlatformNavigation(
          context: ctx,
          selectedIndex: 0,
          onItemSelected: (_) {},
          items: auditItems(count: count),
        ),
        size: const Size(800, 600),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);

      for (int i = 0; i < count; i++) {
        await press(tester, LogicalKeyboardKey.tab);
      }
      expect(ringed(tester), <int>[count - 1]);
      // Focus scrolled the last destination into view rather than leaving it clipped.
      final Rect last = tester.getRect(find.text('Item ${count - 1}'));
      expect(last.right, lessThanOrEqualTo(800));
    });
  });

  group('Web drawer', () {
    testWidgets('the menu button opens the drawer, and a destination closes it', (tester) async {
      final selections = <int>[];
      await pumpNavigation(
        tester,
        (ctx) => buildPlatformNavigation(
          context: ctx,
          selectedIndex: 0,
          onItemSelected: selections.add,
          items: auditItems(),
        ),
        size: const Size(400, 800),
      );

      await press(tester, LogicalKeyboardKey.tab);
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        find.descendant(
          of: find.byType(DrawerButton),
          matching: find.byElementPredicate((e) => identical(e, focused)),
        ),
        findsOneWidget,
        reason: 'the menu button is the first stop',
      );
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(Drawer), findsOneWidget, reason: 'Enter on the menu button opens it');

      await press(tester, LogicalKeyboardKey.tab);
      expect(ringed(tester), <int>[0]);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(ringed(tester), <int>[1]);
      await press(tester, LogicalKeyboardKey.enter);

      expect(selections, <int>[1]);
      expect(find.byType(Drawer), findsNothing, reason: 'choosing a destination closes it');
    });
  });

  group('Contrast', () {
    for (final entry in auditThemes.entries) {
      test('focus ring stands 3:1 off the surfaces it is drawn on (${entry.key})', () {
        final ColorScheme scheme = entry.value.colorScheme;
        // The rail and the top menu sit on `surface`; a selected rail destination's ring is drawn
        // over the indicator pill, which is `secondaryContainer`.
        for (final Color background in <Color>[scheme.surface, scheme.secondaryContainer]) {
          expect(contrastRatio(scheme.primary, background), greaterThanOrEqualTo(3.0));
        }
      });

      testWidgets('text meets AA and every target is labelled (${entry.key})', (tester) async {
        final handle = tester.ensureSemantics();
        for (final wide in <bool>[true, false]) {
          await pumpNavigation(
            tester,
            (ctx) => (wide ? buildPlatformNavigation : buildDesktopNavigation)(
              context: ctx,
              selectedIndex: 1,
              onItemSelected: (_) {},
              items: auditItems(),
            ),
            theme: entry.value,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        }
        handle.dispose();
      });
    }
  });
}
