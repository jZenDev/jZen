import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/radio/zen_radio_group.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../support/a11y.dart';

enum Plan { monthly, quarterly, yearly, lifetime }

const List<ZenRadioOption<Plan>> options = <ZenRadioOption<Plan>>[
  ZenRadioOption<Plan>(value: Plan.monthly, label: 'Monthly'),
  ZenRadioOption<Plan>(value: Plan.quarterly, label: 'Quarterly', enabled: false),
  ZenRadioOption<Plan>(value: Plan.yearly, label: 'Yearly', subtitle: 'Two months free'),
  ZenRadioOption<Plan>(value: Plan.lifetime, label: 'Lifetime'),
];

typedef Build =
    Widget Function(
      BuildContext context,
      String label,
      List<ZenRadioOption<Plan>> options,
      Plan? value,
      ValueChanged<Plan>? onChanged,
    );

final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialRadioGroup<Plan>,
  'cupertino': buildCupertinoRadioGroup<Plan>,
};

Widget radioGroup(
  Build build, {
  Plan? value,
  ValueChanged<Plan>? onChanged,
  List<ZenRadioOption<Plan>> choices = options,
}) => Builder(
  builder: (BuildContext context) => build(context, 'Billing', choices, value, onChanged),
);

/// The radio nodes the user can land on: every merged node that offers a tap and is a member of
/// a mutually exclusive group.
List<SemanticsData> radios(WidgetTester tester) => nodesWith(
  tester,
  SemanticsAction.tap,
).where((SemanticsData d) => d.flagsCollection.isInMutuallyExclusiveGroup).toList();

void main() {
  testWidgets('the public widget follows the compile-time platform', (tester) async {
    await pumpApp(
      tester,
      ZenRadioGroup<Plan>(label: 'Billing', options: options, value: null, onChanged: (_) {}),
    );
    expect(find.byType(RadioListTile<Plan>), zenIsApplePlatform ? findsNothing : findsNWidgets(4));
    expect(find.text('Billing'), findsOneWidget);
  });

  testWidgets('rejects a group with duplicate values or a single option', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ZenRadioGroup<Plan>(
          label: 'Billing',
          options: const <ZenRadioOption<Plan>>[
            ZenRadioOption<Plan>(value: Plan.monthly, label: 'A'),
          ],
          value: null,
          onChanged: (_) {},
        ),
      ),
    );
    expect(tester.takeException(), isAssertionError);
  });

  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('each option is one named radio; only the chosen one is selected', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, radioGroup(entry.value, value: Plan.yearly, onChanged: (_) {}));

        final List<SemanticsData> nodes = radios(tester);
        expect(nodes, hasLength(3), reason: 'the disabled option has no tap action');
        for (final SemanticsData data in nodes) {
          expect(data.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
          final bool yearly = data.label.contains('Yearly');
          expect(
            data.flagsCollection.isChecked,
            yearly ? CheckedState.isTrue : CheckedState.isFalse,
            reason: data.label,
          );
          expect(isEnabled(data), isTrue);
        }
        expect(nodes.map((d) => occurrences(d.label, 'Yearly')).reduce((a, b) => a + b), 1);
        handle.dispose();
      });

      testWidgets('the group is named once and a disabled option reads as disabled', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, radioGroup(entry.value, value: Plan.monthly, onChanged: (_) {}));

        final SemanticsNode quarterly = tester.getSemantics(find.text('Quarterly').first);
        expect(isEnabled(quarterly.getSemanticsData()), isFalse);
        expect(quarterly.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);

        final Iterable<String> labels = <String>[
          for (final SemanticsData d in nodesWith(tester, SemanticsAction.tap)) d.label,
        ];
        expect(labels.where((String l) => l.contains('Billing')), isEmpty);
        // Named exactly once across the whole tree.
        int named = 0;
        void visit(SemanticsNode n) {
          if (n.label == 'Billing') named++;
          n.visitChildren((SemanticsNode c) {
            visit(c);
            return true;
          });
        }

        visit(rootSemantics(tester));
        expect(named, 1);
        handle.dispose();
      });

      testWidgets('a null value selects nothing and reports nothing', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final List<Plan> seen = <Plan>[];
        await pumpApp(tester, radioGroup(entry.value, onChanged: seen.add));
        for (final SemanticsData data in radios(tester)) {
          expect(data.flagsCollection.isChecked, CheckedState.isFalse, reason: data.label);
        }
        expect(seen, isEmpty);
        handle.dispose();
      });

      testWidgets('tapping an option or its label chooses it once', (tester) async {
        final List<Plan> seen = <Plan>[];
        await pumpApp(tester, radioGroup(entry.value, value: Plan.monthly, onChanged: seen.add));
        await tester.tap(find.text('Yearly'));
        expect(seen, <Plan>[Plan.yearly]);
        await tester.tap(find.text('Lifetime'));
        expect(seen, <Plan>[Plan.yearly, Plan.lifetime]);
      });

      testWidgets('a disabled option cannot be chosen', (tester) async {
        final List<Plan> seen = <Plan>[];
        await pumpApp(tester, radioGroup(entry.value, value: Plan.monthly, onChanged: seen.add));
        await tester.tap(find.text('Quarterly'));
        expect(seen, isEmpty);
      });

      testWidgets('a disabled group offers no tap action and cannot be chosen', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, radioGroup(entry.value, value: Plan.monthly));
        expect(radios(tester), isEmpty);
        await tester.tap(find.text('Yearly'));
        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing).first), isFalse);
        handle.dispose();
      });

      testWidgets('Tab enters on the selected option, arrows move the choice and skip disabled', (
        tester,
      ) async {
        Plan? chosen = Plan.yearly;
        await pumpApp(
          tester,
          StatefulBuilder(
            builder: (BuildContext context, StateSetter set) => Column(
              children: <Widget>[
                radioGroup(
                  entry.value,
                  value: chosen,
                  onChanged: (Plan p) => set(() => chosen = p),
                ),
                const TextField(key: Key('after')),
              ],
            ),
          ),
        );
        Finder ring(String label) =>
            find.ancestor(of: find.text(label), matching: find.byType(FocusRing));

        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, ring('Yearly').first), isTrue, reason: 'lands on the selection');

        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(chosen, Plan.lifetime);
        expect(isRinged(tester, ring('Lifetime').first), isTrue);

        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(chosen, Plan.monthly, reason: 'wraps around');
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(chosen, Plan.yearly, reason: 'the disabled Quarterly is skipped');
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(chosen, Plan.monthly);

        // One tab stop for the whole group.
        await press(tester, LogicalKeyboardKey.tab);
        expect(
          FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>(),
          isNotNull,
        );
      }, semanticsEnabled: false);

      testWidgets('with nothing selected Tab lands on the first enabled option', (tester) async {
        await pumpApp(tester, radioGroup(entry.value, onChanged: (_) {}));
        await press(tester, LogicalKeyboardKey.tab);
        final Finder first = find.ancestor(
          of: find.text('Monthly'),
          matching: find.byType(FocusRing),
        );
        expect(isRinged(tester, first.first), isTrue);
      }, semanticsEnabled: false);

      testWidgets('long labels fit at 200% on a narrow screen', (tester) async {
        await pumpApp(
          tester,
          radioGroup(
            entry.value,
            value: Plan.monthly,
            onChanged: (_) {},
            choices: const <ZenRadioOption<Plan>>[
              ZenRadioOption<Plan>(
                value: Plan.monthly,
                label: 'A very long localized option label that has to wrap across lines',
                subtitle: 'And an equally long explanation that also has to wrap on a small screen',
              ),
              ZenRadioOption<Plan>(value: Plan.yearly, label: 'Short'),
            ],
          ),
          size: const Size(260, 900),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('each option is at least 48 logical pixels tall', (tester) async {
        await pumpApp(tester, radioGroup(entry.value, value: Plan.monthly, onChanged: (_) {}));
        for (final Element e in find.byType(FocusRing).evaluate()) {
          expect(e.size!.height, greaterThanOrEqualTo(48));
        }
      });

      if (entry.key == 'cupertino') {
        testWidgets('does not paint a Material splash or highlight', (tester) async {
          await pumpApp(tester, radioGroup(entry.value, value: Plan.monthly, onChanged: (_) {}));
          for (final InkWell ink in tester.widgetList<InkWell>(find.byType(InkWell))) {
            expect(ink.splashFactory, NoSplash.splashFactory);
            expect(ink.highlightColor, Colors.transparent);
          }
        });
      }

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA text contrast (${theme.key})', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpApp(
            tester,
            radioGroup(entry.value, value: Plan.yearly, onChanged: (_) {}),
            theme: theme.value,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    });
  }
}
