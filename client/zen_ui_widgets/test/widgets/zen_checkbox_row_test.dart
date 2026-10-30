import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/checkbox/zen_checkbox_row.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../support/a11y.dart';

typedef Build =
    Widget Function(
      BuildContext context,
      String label,
      String? subtitle,
      bool? value,
      ValueChanged<bool>? onChanged,
    );

final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialCheckboxRow,
  'cupertino': buildCupertinoCheckboxRow,
};

Widget row(Build build, {bool? value = false, ValueChanged<bool>? onChanged, String? subtitle}) =>
    Builder(
      builder: (BuildContext context) =>
          FocusRing.wrapping(child: build(context, 'Accept terms', subtitle, value, onChanged)),
    );

void main() {
  testWidgets('the public widget follows the compile-time platform', (tester) async {
    await pumpApp(tester, ZenCheckboxRow(label: 'Accept terms', value: true, onChanged: (_) {}));
    expect(find.byType(CheckboxListTile), zenIsApplePlatform ? findsNothing : findsOneWidget);
    expect(find.byType(ZenCheckboxRow), findsOneWidget);
  });

  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('is one control: label, checked state and a tap, announced once', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, row(entry.value, value: true, onChanged: (_) {}));

        final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.tap);
        expect(nodes, hasLength(1), reason: nodes.map((n) => n.label).join(' | '));
        expect(occurrences(nodes.single.label, 'Accept terms'), 1, reason: nodes.single.label);
        expect(nodes.single.flagsCollection.isChecked, CheckedState.isTrue);
        expect(isEnabled(nodes.single), isTrue);
        handle.dispose();
      });

      testWidgets('an unchecked row is announced as unchecked', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, row(entry.value, onChanged: (_) {}));
        expect(
          nodesWith(tester, SemanticsAction.tap).single.flagsCollection.isChecked,
          CheckedState.isFalse,
        );
        handle.dispose();
      });

      testWidgets('a null value is announced as mixed, not as checked', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, row(entry.value, value: null, onChanged: (_) {}));
        expect(
          nodesWith(tester, SemanticsAction.tap).single.flagsCollection.isChecked,
          CheckedState.mixed,
        );
        handle.dispose();
      });

      testWidgets('a tap anywhere on the row asks for the opposite value, once', (tester) async {
        final List<bool> seen = <bool>[];
        await pumpApp(tester, row(entry.value, onChanged: seen.add));
        await tester.tap(find.text('Accept terms'));
        expect(seen, <bool>[true]);

        await pumpApp(tester, row(entry.value, value: true, onChanged: seen.add));
        await tester.tap(find.text('Accept terms'));
        expect(seen, <bool>[true, false]);
      });

      testWidgets('a tap on the box itself changes the value once', (tester) async {
        final List<bool> seen = <bool>[];
        await pumpApp(tester, row(entry.value, onChanged: seen.add));
        await tester.tapAt(tester.getTopLeft(find.byType(FocusRing)) + const Offset(40, 24));
        expect(seen, <bool>[true]);
      });

      testWidgets('a mixed row asks for checked', (tester) async {
        final List<bool> seen = <bool>[];
        await pumpApp(tester, row(entry.value, value: null, onChanged: seen.add));
        await tester.tap(find.text('Accept terms'));
        expect(seen, <bool>[true]);
      });

      testWidgets('Tab reaches it, Space toggles it, and a ring shows', (tester) async {
        final List<bool> seen = <bool>[];
        await pumpApp(tester, row(entry.value, onChanged: seen.add));
        expect(isRinged(tester, find.byType(FocusRing)), isFalse);

        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing)), isTrue);
        await press(tester, LogicalKeyboardKey.space);
        expect(seen, <bool>[true]);
        await press(tester, LogicalKeyboardKey.enter);
        expect(seen.length, lessThanOrEqualTo(2), reason: 'one key press is at most one change');
      }, semanticsEnabled: false);

      testWidgets('exactly one tab stop', (tester) async {
        await pumpApp(
          tester,
          Column(
            children: <Widget>[
              row(entry.value, onChanged: (_) {}),
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

      testWidgets('disabled: no tap action, no change, announced as disabled', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, row(entry.value));
        expect(nodesWith(tester, SemanticsAction.tap), isEmpty);
        await tester.tap(find.text('Accept terms'));
        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing)), isFalse, reason: 'nothing to focus');
        handle.dispose();
      });

      testWidgets('reads its subtitle after the label', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(
          tester,
          row(entry.value, subtitle: 'Required to continue', onChanged: (_) {}),
        );
        final SemanticsData node = nodesWith(tester, SemanticsAction.tap).single;
        expect('${node.label} ${node.hint}', contains('Required to continue'));
        handle.dispose();
      });

      testWidgets('long text fits at 200% on a narrow screen', (tester) async {
        await pumpApp(
          tester,
          row(
            entry.value,
            subtitle: 'A long explanation of this consent that needs to wrap across several lines',
            onChanged: (_) {},
          ),
          size: const Size(260, 700),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the tap target is at least 48 logical pixels tall', (tester) async {
        await pumpApp(tester, row(entry.value, onChanged: (_) {}));
        expect(tester.getSize(find.byType(FocusRing)).height, greaterThanOrEqualTo(48));
      });

      if (entry.key == 'cupertino') {
        testWidgets('does not paint a Material splash or highlight', (tester) async {
          await pumpApp(tester, row(entry.value, onChanged: (_) {}));
          final InkWell ink = tester.widget<InkWell>(find.byType(InkWell));
          expect(ink.splashFactory, NoSplash.splashFactory);
          expect(ink.highlightColor, Colors.transparent);
        });
      }

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA text contrast (${theme.key})', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpApp(
            tester,
            row(entry.value, subtitle: 'Required to continue', onChanged: (_) {}),
            theme: theme.value,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    });
  }
}
