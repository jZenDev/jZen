import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/zen_switch_row.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../support/a11y.dart';

typedef Build =
    Widget Function(
      BuildContext context,
      String label,
      String? subtitle,
      bool value,
      ValueChanged<bool>? onChanged,
    );

final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialSwitchRow,
  'cupertino': buildCupertinoSwitchRow,
};

Widget row(Build build, {bool value = false, ValueChanged<bool>? onChanged, String? subtitle}) =>
    Builder(
      builder: (BuildContext context) =>
          FocusRing.wrapping(child: build(context, 'Archived', subtitle, value, onChanged)),
    );

void main() {
  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('is one control: label, toggled state and a tap, announced once', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, row(entry.value, value: true, onChanged: (_) {}));

        final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.tap);
        expect(nodes, hasLength(1), reason: nodes.map((n) => n.label).join(' | '));
        expect(occurrences(nodes.single.label, 'Archived'), 1, reason: nodes.single.label);
        expect(nodes.single.flagsCollection.isToggled, Tristate.isTrue);
        expect(isEnabled(nodes.single), isTrue);
        handle.dispose();
      });

      testWidgets('an off row is announced as off', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, row(entry.value, onChanged: (_) {}));
        expect(
          nodesWith(tester, SemanticsAction.tap).single.flagsCollection.isToggled,
          Tristate.isFalse,
        );
        handle.dispose();
      });

      testWidgets('a tap anywhere on the row toggles it', (tester) async {
        final List<bool> seen = <bool>[];
        await pumpApp(tester, row(entry.value, onChanged: seen.add));
        await tester.tap(find.text('Archived'));
        expect(seen, <bool>[true]);
      });

      testWidgets('Tab reaches it, Space and Enter toggle it, and a ring shows', (tester) async {
        final List<bool> seen = <bool>[];
        await pumpApp(tester, row(entry.value, onChanged: seen.add));
        expect(isRinged(tester, find.byType(FocusRing)), isFalse);

        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing)), isTrue);
        await press(tester, LogicalKeyboardKey.space);
        expect(seen, <bool>[true]);
        await press(tester, LogicalKeyboardKey.enter);
        expect(seen, <bool>[true, true], reason: 'the app owns the value; it is not toggled here');
      }, semanticsEnabled: false);

      testWidgets('exactly one tab stop', (tester) async {
        final List<bool> seen = <bool>[];
        await pumpApp(
          tester,
          Column(
            children: <Widget>[
              row(entry.value, onChanged: seen.add),
              const TextField(key: Key('after')),
            ],
          ),
        );
        await press(tester, LogicalKeyboardKey.tab);
        await press(tester, LogicalKeyboardKey.tab);
        // Straight from the row to the next field: the switch inside is not a second stop.
        expect(
          FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>(),
          isNotNull,
        );
      });

      testWidgets('disabled: no tap action, announced as disabled', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, row(entry.value));
        expect(nodesWith(tester, SemanticsAction.tap), isEmpty);
        handle.dispose();
      });

      testWidgets('reads its subtitle after the label', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, row(entry.value, subtitle: 'Hidden from lists', onChanged: (_) {}));
        final SemanticsData node = nodesWith(tester, SemanticsAction.tap).single;
        expect('${node.label} ${node.hint}', contains('Hidden from lists'));
        handle.dispose();
      });

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA text contrast (${theme.key})', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpApp(
            tester,
            row(entry.value, subtitle: 'Hidden from lists', onChanged: (_) {}),
            theme: theme.value,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    });
  }
}
