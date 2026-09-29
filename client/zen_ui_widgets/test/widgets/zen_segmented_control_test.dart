import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/zen_segmented_control.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../support/a11y.dart';

enum Kind { expense, income, transfer }

const List<ZenSegment<Kind>> segments = <ZenSegment<Kind>>[
  ZenSegment<Kind>(value: Kind.expense, label: 'Expense'),
  ZenSegment<Kind>(value: Kind.income, label: 'Income'),
  ZenSegment<Kind>(value: Kind.transfer, label: 'Transfer'),
];

typedef Build =
    Widget Function(
      BuildContext context,
      List<ZenSegment<Kind>> segments,
      Kind selected,
      ValueChanged<Kind>? onChanged,
    );

final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialSegmentedControl<Kind>,
  'cupertino': buildCupertinoSegmentedControl<Kind>,
};

/// Wraps the way the public widget does: Cupertino rings the whole control (focus is the choice),
/// Material rings inside each segment.
Widget control(
  Build build, {
  required bool wrapped,
  Kind selected = Kind.income,
  ValueChanged<Kind>? onChanged,
}) => Builder(
  builder: (BuildContext context) => wrapped
      ? FocusRing.wrapping(child: build(context, segments, selected, onChanged))
      : build(context, segments, selected, onChanged),
);

void main() {
  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('each segment is one named control and only the chosen one is selected', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(
          tester,
          control(entry.value, wrapped: entry.key == 'cupertino', onChanged: (_) {}),
        );

        for (final ZenSegment<Kind> segment in segments) {
          final SemanticsNode node = tester.getSemantics(find.text(segment.label));
          final SemanticsData data = node.getSemanticsData();
          expect(occurrences(data.label, segment.label), 1, reason: data.label);
          expect(
            data.flagsCollection.isSelected,
            segment.value == Kind.income ? Tristate.isTrue : Tristate.isFalse,
            reason: segment.label,
          );
        }
        handle.dispose();
      });

      testWidgets('tapping a segment reports its value', (tester) async {
        final List<Kind> seen = <Kind>[];
        await pumpApp(
          tester,
          control(entry.value, wrapped: entry.key == 'cupertino', onChanged: seen.add),
        );
        await tester.tap(find.text('Transfer'));
        await tester.pumpAndSettle();
        expect(seen, <Kind>[Kind.transfer]);
      });

      testWidgets('the keyboard reaches the segments, a ring marks the focused one', (
        tester,
      ) async {
        Kind selected = Kind.income;
        await pumpApp(
          tester,
          StatefulBuilder(
            builder: (BuildContext context, StateSetter set) => control(
              entry.value,
              wrapped: entry.key == 'cupertino',
              selected: selected,
              onChanged: (Kind kind) => set(() => selected = kind),
            ),
          ),
        );
        Finder ring(String label) =>
            find.ancestor(of: find.text(label), matching: find.byType(FocusRing));
        expect(isRinged(tester, find.byType(FocusRing).first), isFalse);

        // Cupertino's control is a radio group: Tab lands on the chosen segment and the arrows
        // move the choice; the whole control carries one ring. Material's segments are separate
        // tab stops, each with its own ring, so Tab walks them and each shows in turn.
        if (entry.key == 'cupertino') {
          await press(tester, LogicalKeyboardKey.tab);
          expect(isRinged(tester, find.byType(FocusRing)), isTrue);
          await press(tester, LogicalKeyboardKey.arrowRight);
          expect(selected, Kind.transfer, reason: 'the arrows move the choice');
          expect(isRinged(tester, find.byType(FocusRing)), isTrue);
        } else {
          final Set<String> reached = <String>{};
          for (int i = 0; i < 3; i++) {
            await press(tester, LogicalKeyboardKey.tab);
            for (final ZenSegment<Kind> segment in segments) {
              if (isRinged(tester, ring(segment.label).first)) reached.add(segment.label);
            }
          }
          expect(reached, <String>{'Expense', 'Income', 'Transfer'});
        }
      }, semanticsEnabled: false);

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA text contrast (${theme.key})', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpApp(
            tester,
            control(entry.value, wrapped: entry.key == 'cupertino', onChanged: (_) {}),
            theme: theme.value,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    });
  }
}
