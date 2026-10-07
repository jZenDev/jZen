import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_sidebar.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

import '../support/a11y.dart';

/// The macOS sidebar, built directly: the public shell chooses it on a compile-time constant, so
/// a run on Linux would never reach it. It carries what the rail does (semantics, keyboard, ring,
/// contrast, 200% text), which is why this suite has the shape of the rail's and of
/// `zen_button_test.dart`.
Widget sidebar(
  BuildContext context, {
  int selected = 1,
  ValueChanged<int>? onSelected,
  ValueChanged<String>? onSelectedId,
  List<ZenNavigationItem>? items,
}) => buildSidebarNavigation(
  context: context,
  selectedIndex: selected,
  onItemSelected: onSelected ?? (_) {},
  onItemSelectedId: onSelectedId,
  items: items ?? auditItems(),
);

void main() {
  group('semantics', () {
    testWidgets('one node per destination: named once, its badge as a value, position as a hint', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpNavigation(tester, sidebar);

      final List<SemanticsData> nodes = <SemanticsData>[
        for (final SemanticsData node in actionableNodes(tester))
          if (node.label.contains('Item ')) node,
      ];
      expect(nodes, hasLength(3), reason: 'one actionable node per destination');
      for (int i = 0; i < 3; i++) {
        final SemanticsData node = nodes[i];
        expect(occurrences(node.label, 'Item $i'), 1, reason: 'label "${node.label}" repeats');
        expect(node.flagsCollection.isButton, isTrue);
        expect(
          node.flagsCollection.isSelected,
          i == 1 ? ui.Tristate.isTrue : ui.Tristate.isFalse,
          reason: 'selected state on destination $i',
        );
        expect(node.hint, '${i + 1} of 3', reason: 'position of destination $i');
      }
      expect(nodes.last.value, '4 new', reason: 'the badge is read after the label');
      handle.dispose();
    });

    testWidgets('the menu is a navigation landmark and the page is main', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpNavigation(tester, sidebar);

      final List<ui.SemanticsRole> roles = <ui.SemanticsRole>[];
      bool visit(SemanticsNode node) {
        roles.add(node.getSemanticsData().role);
        node.visitChildren(visit);
        return true;
      }

      visit(rootSemantics(tester));
      expect(
        roles,
        containsAll(<ui.SemanticsRole>[ui.SemanticsRole.navigation, ui.SemanticsRole.main]),
      );
      handle.dispose();
    });

    testWidgets('the position is spoken in Ukrainian too', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      tester.platformDispatcher.localesTestValue = const <Locale>[Locale('uk')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await pumpNavigation(tester, sidebar);

      expect(<String>[
        for (final SemanticsData n in actionableNodes(tester)) n.hint,
      ], contains('2 з 3'));
      handle.dispose();
    });
  });

  group('pointer', () {
    testWidgets('a tap selects, and reports the id', (tester) async {
      int? index;
      String? id;
      await pumpNavigation(
        tester,
        (context) => sidebar(
          context,
          selected: 0,
          onSelected: (i) => index = i,
          onSelectedId: (v) => id = v,
        ),
      );

      await tester.tap(find.text('Item 2'));
      expect(index, 2);
      expect(id, 'id_2');
    });

    testWidgets('the selected destination is highlighted and the page follows the selection', (
      tester,
    ) async {
      await pumpNavigation(tester, (context) => sidebar(context, selected: 2));

      final ColorScheme scheme = Theme.of(tester.element(find.text('Item 0'))).colorScheme;
      Color? fill(String label) {
        final Finder box = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color != null,
          ),
        );
        return box.evaluate().isEmpty
            ? null
            : ((box.evaluate().first.widget as DecoratedBox).decoration as BoxDecoration).color;
      }

      expect(fill('Item 2'), scheme.secondaryContainer);
      expect(fill('Item 0'), isNull);
      expect(find.text('page_2'), findsOneWidget);
    });
  });

  group('keyboard', () {
    testWidgets('Tab, arrows, Enter and Space reach and activate every destination', (
      tester,
    ) async {
      final List<int> selections = <int>[];
      await pumpNavigation(
        tester,
        (context) => sidebar(context, selected: 0, onSelected: selections.add),
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
    }, semanticsEnabled: false);

    for (final PointerDeviceKind kind in <PointerDeviceKind>[
      PointerDeviceKind.mouse,
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
    ]) {
      testWidgets('a ${kind.name} press clears the ring, and a key press restores it', (
        tester,
      ) async {
        await pumpNavigation(tester, (context) => sidebar(context, selected: 0));
        await press(tester, LogicalKeyboardKey.tab);
        expect(ringed(tester), <int>[0]);

        await tester.tap(find.text('Item 1'), kind: kind);
        await tester.pumpAndSettle();
        expect(ringed(tester), isEmpty, reason: 'no ring after a ${kind.name} press');

        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(ringed(tester), hasLength(1), reason: 'keyboard input shows focus again');
      }, semanticsEnabled: false);
    }

    testWidgets('with assistive technology attached the ring shows despite a mouse click', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpNavigation(tester, (context) => sidebar(context, selected: 0));
      await tester.tap(find.text('Item 1'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      // Focus moved the way assistive technology moves it: a semantics action, no key event.
      final SemanticsNode node = tester.getSemantics(find.text('Item 2'));
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.focus,
      );
      await tester.pumpAndSettle();
      expect(ringed(tester), <int>[2]);
      handle.dispose();
    });
  });

  group('layout', () {
    testWidgets(
      'at 200% text on a narrow window nothing overflows and every destination is reachable',
      (tester) async {
        const int count = 8;
        await pumpNavigation(
          tester,
          (context) => sidebar(context, selected: 0, items: auditItems(count: count)),
          size: const Size(480, 400),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);

        for (int i = 0; i < count; i++) {
          await press(tester, LogicalKeyboardKey.tab);
        }
        expect(ringed(tester), <int>[count - 1]);
        // Focus scrolled the last destination into view rather than leaving it below the fold.
        expect(tester.getRect(find.text('Item ${count - 1}')).bottom, lessThanOrEqualTo(400));
        expect(tester.takeException(), isNull);
      },
      semanticsEnabled: false,
    );

    testWidgets('the sidebar stays within two fifths of the window', (tester) async {
      await pumpNavigation(tester, sidebar, size: const Size(400, 600), textScale: 2);
      expect(tester.getSize(find.byType(NavigationSidebar)).width, lessThanOrEqualTo(160));
    });
  });

  group('contrast', () {
    for (final MapEntry<String, ThemeData> entry in auditThemes.entries) {
      test('the focus ring stands 3:1 off the sidebar and the selected row (${entry.key})', () {
        final ColorScheme scheme = entry.value.colorScheme;
        for (final Color background in <Color>[
          scheme.surfaceContainerLow,
          scheme.secondaryContainer,
        ]) {
          expect(contrastRatio(scheme.primary, background), greaterThanOrEqualTo(3.0));
        }
      });

      testWidgets('text meets AA and every target is labelled (${entry.key})', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpNavigation(tester, sidebar, theme: entry.value);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }
  });
}
