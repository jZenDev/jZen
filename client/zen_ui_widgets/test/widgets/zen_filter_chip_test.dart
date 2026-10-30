import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show CheckedState, Tristate;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/chip/zen_filter_chip.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../support/a11y.dart';

typedef Build =
    Widget Function(
      BuildContext context,
      String label,
      bool selected,
      ValueChanged<bool>? onSelected,
    );

final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialFilterChip,
  'cupertino': buildCupertinoFilterChip,
};

Widget chip(Build build, String label, {bool selected = false, ValueChanged<bool>? onSelected}) =>
    Builder(builder: (BuildContext context) => build(context, label, selected, onSelected));

void main() {
  testWidgets('the public widget follows the compile-time platform', (tester) async {
    await pumpApp(tester, ZenFilterChip(label: 'Groceries', selected: false, onSelected: (_) {}));
    expect(find.byType(FilterChip), zenIsApplePlatform ? findsNothing : findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
  });

  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('is one button named once, with its selected state', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(
          tester,
          Column(
            children: <Widget>[
              chip(entry.value, 'Groceries', selected: true, onSelected: (_) {}),
              chip(entry.value, 'Travel', onSelected: (_) {}),
            ],
          ),
        );
        final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.tap);
        expect(nodes, hasLength(2));
        final SemanticsData groceries = nodes.firstWhere((d) => d.label.contains('Groceries'));
        final SemanticsData travel = nodes.firstWhere((d) => d.label.contains('Travel'));
        expect(occurrences(groceries.label, 'Groceries'), 1, reason: groceries.label);
        // Material on the web announces a filter chip as a checkable button, not a selected one.
        bool on(SemanticsData d) =>
            d.flagsCollection.isSelected == Tristate.isTrue ||
            d.flagsCollection.isChecked == CheckedState.isTrue;
        expect(on(groceries), isTrue);
        expect(on(travel), isFalse);
        expect(groceries.flagsCollection.isButton, isTrue);
        expect(isEnabled(groceries), isTrue);
        handle.dispose();
      });

      testWidgets('selection does not rely on colour: a check mark appears', (tester) async {
        await pumpApp(tester, chip(entry.value, 'Groceries', onSelected: (_) {}));
        final Finder mark = entry.key == 'cupertino'
            ? find.byIcon(CupertinoIcons.checkmark_alt)
            : find.byWidgetPredicate((Widget w) => w is FilterChip && w.showCheckmark == true);
        if (entry.key == 'cupertino') expect(mark, findsNothing);
        await pumpApp(tester, chip(entry.value, 'Groceries', selected: true, onSelected: (_) {}));
        expect(mark, findsOneWidget);
      });

      testWidgets('a tap asks for the opposite value once; chips are independent', (tester) async {
        final Set<String> on = <String>{'Groceries'};
        await pumpApp(
          tester,
          StatefulBuilder(
            builder: (BuildContext context, StateSetter set) => Column(
              children: <Widget>[
                for (final String name in <String>['Groceries', 'Travel', 'Rent'])
                  chip(
                    entry.value,
                    name,
                    selected: on.contains(name),
                    onSelected: (bool v) => set(() => v ? on.add(name) : on.remove(name)),
                  ),
              ],
            ),
          ),
        );
        await tester.tap(find.text('Travel'));
        await tester.pumpAndSettle();
        expect(on, <String>{'Groceries', 'Travel'});
        await tester.tap(find.text('Groceries'));
        await tester.pumpAndSettle();
        expect(on, <String>{'Travel'});
      });

      testWidgets('Tab reaches it, Space and Enter activate it, and a ring shows', (tester) async {
        final List<bool> seen = <bool>[];
        await pumpApp(tester, chip(entry.value, 'Groceries', onSelected: seen.add));
        expect(isRinged(tester, find.byType(FocusRing)), isFalse);
        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing)), isTrue);
        await press(tester, LogicalKeyboardKey.space);
        expect(seen, <bool>[true]);
        await press(tester, LogicalKeyboardKey.enter);
        expect(seen, <bool>[true, true]);
      }, semanticsEnabled: false);

      testWidgets('exactly one tab stop per chip', (tester) async {
        await pumpApp(
          tester,
          Column(
            children: <Widget>[
              chip(entry.value, 'Groceries', onSelected: (_) {}),
              const TextField(key: Key('after')),
            ],
          ),
        );
        await press(tester, LogicalKeyboardKey.tab);
        await press(tester, LogicalKeyboardKey.tab);
        expect(
          FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>(),
          isNotNull,
        );
      });

      testWidgets('disabled: no tap action, no callback, not focusable', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, chip(entry.value, 'Groceries'));
        expect(nodesWith(tester, SemanticsAction.tap), isEmpty);
        await tester.tap(find.text('Groceries'));
        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing)), isFalse);
        final SemanticsData data = tester.getSemantics(find.text('Groceries')).getSemanticsData();
        expect(isEnabled(data), isFalse);
        handle.dispose();
      });

      testWidgets('at least 44 logical pixels tall', (tester) async {
        await pumpApp(tester, chip(entry.value, 'Groceries', onSelected: (_) {}));
        expect(tester.getSize(find.byType(FocusRing)).height, greaterThanOrEqualTo(44));
      });

      testWidgets('chips wrap onto new lines and long labels wrap inside the chip', (tester) async {
        await pumpApp(
          tester,
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final String name in <String>[
                'Groceries and household supplies for the whole month',
                'Travel',
                'Rent',
                'Utilities',
              ])
                chip(entry.value, name, selected: name == 'Travel', onSelected: (_) {}),
            ],
          ),
          size: const Size(220, 900),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        final double widest = tester
            .getSize(
              find
                  .ancestor(of: find.textContaining('Groceries'), matching: find.byType(FocusRing))
                  .first,
            )
            .width;
        expect(widest, lessThanOrEqualTo(220 - 48));
      });

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA text contrast, selected and not (${theme.key})', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpApp(
            tester,
            Column(
              children: <Widget>[
                chip(entry.value, 'Groceries', selected: true, onSelected: (_) {}),
                chip(entry.value, 'Travel', onSelected: (_) {}),
              ],
            ),
            theme: theme.value,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }

      if (entry.key == 'cupertino') {
        testWidgets('does not paint a Material splash or highlight', (tester) async {
          await pumpApp(tester, chip(entry.value, 'Groceries', onSelected: (_) {}));
          final InkWell ink = tester.widget<InkWell>(find.byType(InkWell));
          expect(ink.splashFactory, NoSplash.splashFactory);
          expect(ink.highlightColor, Colors.transparent);
        });
      }
    });
  }
}
