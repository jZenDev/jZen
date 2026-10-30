import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/slider/zen_range_slider.dart';
import 'package:zen_ui_widgets/src/slider/zen_range_slider_body.dart';

import '../support/a11y.dart';

typedef Build =
    Widget Function(
      BuildContext context,
      String label,
      String startLabel,
      String endLabel,
      RangeValues values,
      double min,
      double max,
      int? divisions,
      String Function(double) format,
      ValueChanged<RangeValues>? onChanged,
    );

final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialRangeSlider,
  'cupertino': buildCupertinoRangeSlider,
};

String eur(double v) => '€${v.round()}';

/// A range slider whose state lives in the test, followed by a field to tab out to.
class Harness {
  Harness(this.build, {RangeValues start = const RangeValues(20, 80), this.divisions}) {
    values = start;
  }

  final Build build;
  final int? divisions;
  late RangeValues values;
  final List<RangeValues> seen = <RangeValues>[];

  Widget widget({bool enabled = true}) => StatefulBuilder(
    builder: (BuildContext context, StateSetter set) => Column(
      children: <Widget>[
        build(
          context,
          'Price',
          'Minimum price',
          'Maximum price',
          values,
          0,
          100,
          divisions,
          eur,
          enabled
              ? (RangeValues next) {
                  seen.add(next);
                  set(() => values = next);
                }
              : null,
        ),
        const TextField(key: Key('after')),
      ],
    ),
  );
}

List<SemanticsData> thumbs(WidgetTester tester) => nodesWith(tester, SemanticsAction.increase);

void perform(WidgetTester tester, String label, SemanticsAction action) {
  SemanticsNode? found;
  bool visit(SemanticsNode node) {
    if (!node.isMergedIntoParent && node.label == label) found = node;
    node.visitChildren(visit);
    return true;
  }

  visit(rootSemantics(tester));
  tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(found!.id, action);
}

Finder thumbFinder(String label) => find.bySemanticsLabel(label);

void main() {
  testWidgets('the public widget follows the compile-time platform', (tester) async {
    await pumpApp(
      tester,
      ZenRangeSlider(
        label: 'Price',
        startLabel: 'Minimum price',
        endLabel: 'Maximum price',
        values: const RangeValues(20, 80),
        min: 0,
        max: 100,
        valueFormatter: eur,
        onChanged: (_) {},
      ),
    );
    final ZenRangeSliderBody body = tester.widget(find.byType(ZenRangeSliderBody));
    expect(body.style.thumbDiameter, zenIsApplePlatform ? 28 : 20);
    expect(find.text('€20 – €80'), findsOneWidget);
  });

  test('invalid bounds and an inverted range are rejected', () {
    expect(
      () => ZenRangeSlider(
        label: 'p',
        startLabel: 'a',
        endLabel: 'b',
        values: const RangeValues(0, 1),
        min: 3,
        max: 3,
        onChanged: (_) {},
      ),
      throwsAssertionError,
    );
  });

  testWidgets('an inverted or out-of-range value is shown clamped and not reported', (
    tester,
  ) async {
    final List<RangeValues> seen = <RangeValues>[];
    await pumpApp(
      tester,
      ZenRangeSlider(
        label: 'Price',
        startLabel: 'Minimum price',
        endLabel: 'Maximum price',
        values: const RangeValues(-50, 500),
        min: 0,
        max: 100,
        onChanged: seen.add,
      ),
    );
    expect(find.text('0 – 100'), findsOneWidget);
    expect(seen, isEmpty);
  });

  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('two sliders, each named, valued and operable on its own', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, Harness(entry.value, divisions: 10).widget());

        final List<SemanticsData> nodes = thumbs(tester);
        expect(nodes, hasLength(2));
        final SemanticsData start = nodes.firstWhere((d) => d.label == 'Minimum price');
        final SemanticsData end = nodes.firstWhere((d) => d.label == 'Maximum price');
        expect(start.value, '€20');
        expect(start.increasedValue, '€30');
        expect(start.decreasedValue, '€10');
        expect(end.value, '€80');
        expect(start.flagsCollection.isSlider, isTrue);
        expect(isEnabled(start) && isEnabled(end), isTrue);

        // The group is named once, by its own node.
        int groups = 0;
        void visit(SemanticsNode n) {
          if (n.label == 'Price') groups++;
          n.visitChildren((SemanticsNode c) {
            visit(c);
            return true;
          });
        }

        visit(rootSemantics(tester));
        expect(groups, 1);
        handle.dispose();
      });

      testWidgets('the screen reader moves one thumb and keeps the other', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final Harness h = Harness(entry.value, divisions: 10);
        await pumpApp(tester, h.widget());

        perform(tester, 'Minimum price', SemanticsAction.increase);
        await tester.pump();
        expect(h.values, const RangeValues(30, 80));
        perform(tester, 'Maximum price', SemanticsAction.decrease);
        await tester.pump();
        expect(h.values, const RangeValues(30, 70));
        handle.dispose();
      });

      testWidgets('the thumbs may meet but never cross', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final Harness h = Harness(entry.value, start: const RangeValues(40, 50), divisions: 10);
        await pumpApp(tester, h.widget());

        perform(tester, 'Minimum price', SemanticsAction.increase);
        await tester.pump();
        expect(h.values, const RangeValues(50, 50), reason: 'they meet');
        perform(tester, 'Minimum price', SemanticsAction.increase);
        await tester.pump();
        expect(h.values, const RangeValues(50, 50), reason: 'the start stops at the end');
        perform(tester, 'Maximum price', SemanticsAction.decrease);
        await tester.pump();
        expect(h.values, const RangeValues(50, 50), reason: 'the end stops at the start');
        perform(tester, 'Maximum price', SemanticsAction.increase);
        await tester.pump();
        expect(h.values, const RangeValues(50, 60));
        handle.dispose();
      });

      testWidgets('dragging the start past the end stops at the end', (tester) async {
        final Harness h = Harness(entry.value);
        await pumpApp(tester, h.widget());
        final Rect track = tester.getRect(find.byType(ZenRangeSliderBody));

        // Pick up the start thumb (20%) and drag it right across the end thumb (80%).
        final double x20 = track.left + 24 + (track.width - 48) * 0.2;
        await tester.dragFrom(Offset(x20, track.center.dy), Offset(track.width, 0));
        await tester.pump();
        expect(h.values.end, 80, reason: 'the other thumb is untouched');
        expect(h.values.start, 80, reason: 'stops where it meets it');
        for (final RangeValues v in h.seen) {
          expect(v.start <= v.end, isTrue);
        }
      });

      testWidgets('dragging the end below the start stops at the start', (tester) async {
        final Harness h = Harness(entry.value);
        await pumpApp(tester, h.widget());
        final Rect track = tester.getRect(find.byType(ZenRangeSliderBody));
        final double x80 = track.left + 24 + (track.width - 48) * 0.8;
        await tester.dragFrom(Offset(x80, track.center.dy), Offset(-track.width, 0));
        await tester.pump();
        expect(h.values, const RangeValues(20, 20));
      });

      testWidgets('together, a drag moves the thumb that can go that way', (tester) async {
        final Harness h = Harness(entry.value, start: const RangeValues(50, 50));
        await pumpApp(tester, h.widget());
        final Rect track = tester.getRect(find.byType(ZenRangeSliderBody));
        final Offset middle = Offset(track.center.dx, track.center.dy);

        await tester.dragFrom(middle, const Offset(60, 0));
        await tester.pump();
        expect(h.values.start, 50);
        expect(h.values.end, greaterThan(50));

        h.values = const RangeValues(50, 50);
        await tester.pumpWidget(const SizedBox());
        await pumpApp(tester, h.widget());
        await tester.dragFrom(middle, const Offset(-60, 0));
        await tester.pump();
        expect(h.values.end, 50);
        expect(h.values.start, lessThan(50));
      });

      testWidgets('with divisions every reported value is on a step', (tester) async {
        final Harness h = Harness(entry.value, divisions: 10);
        await pumpApp(tester, h.widget());
        final Rect track = tester.getRect(find.byType(ZenRangeSliderBody));
        await tester.dragFrom(
          Offset(track.left + 24 + (track.width - 48) * 0.2, track.center.dy),
          const Offset(90, 0),
        );
        await tester.pump();
        expect(h.seen, isNotEmpty);
        for (final RangeValues v in h.seen) {
          expect(v.start % 10, closeTo(0, 1e-9));
          expect(v.end % 10, closeTo(0, 1e-9));
        }
      });

      testWidgets('a tap moves the nearer thumb only', (tester) async {
        final Harness h = Harness(entry.value);
        await pumpApp(tester, h.widget());
        final Rect track = tester.getRect(find.byType(ZenRangeSliderBody));
        await tester.tapAt(Offset(track.left + 24 + (track.width - 48) * 0.9, track.center.dy));
        await tester.pump();
        expect(h.values.start, 20);
        expect(h.values.end, closeTo(90, 1));
      });

      testWidgets('each thumb is a tab stop with a ring; arrows move only that thumb', (
        tester,
      ) async {
        final Harness h = Harness(entry.value, divisions: 10);
        await pumpApp(tester, h.widget());
        expect(isRinged(tester, find.byType(ZenRangeSliderBody)), isFalse);

        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(ZenRangeSliderBody)), isTrue);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(h.values, const RangeValues(30, 80));

        await press(tester, LogicalKeyboardKey.tab);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(h.values, const RangeValues(30, 70));

        // Home on the end thumb goes as low as the start; End on the start goes as high as the end.
        await press(tester, LogicalKeyboardKey.home);
        expect(h.values, const RangeValues(30, 30));
        await press(tester, LogicalKeyboardKey.tab, shift: true);
        await press(tester, LogicalKeyboardKey.end);
        expect(h.values, const RangeValues(30, 30), reason: 'bounded by the end thumb');
        await press(tester, LogicalKeyboardKey.home);
        expect(h.values, const RangeValues(0, 30));

        // Two stops for the slider, then out.
        await press(tester, LogicalKeyboardKey.tab);
        await press(tester, LogicalKeyboardKey.tab);
        expect(
          FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>(),
          isNotNull,
        );
      }, semanticsEnabled: false);

      testWidgets('disabled: no range actions, not focusable, no change', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final Harness h = Harness(entry.value);
        await pumpApp(tester, h.widget(enabled: false));
        expect(thumbs(tester), isEmpty);
        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(ZenRangeSliderBody)), isFalse);
        final Rect track = tester.getRect(find.byType(ZenRangeSliderBody));
        await tester.dragFrom(Offset(track.center.dx, track.center.dy), const Offset(60, 0));
        expect(h.seen, isEmpty);
        handle.dispose();
      });

      testWidgets('fits a narrow, scaled screen and the track is at least 48 px tall', (
        tester,
      ) async {
        final Harness h = Harness(entry.value);
        await pumpApp(tester, h.widget(), size: const Size(220, 700), textScale: 2);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(ZenRangeSliderBody)).height, greaterThanOrEqualTo(48));
      });

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA text contrast (${theme.key})', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpApp(tester, Harness(entry.value).widget(), theme: theme.value);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });

        test('its track and thumb reach 3:1 against the surface (${theme.key})', () {
          final ZenRangeSliderStyle style = entry.key == 'material'
              ? zenMaterialRangeSliderStyle(theme.value)
              : zenCupertinoRangeSliderStyle(theme.value);
          final Color surface = theme.value.colorScheme.surface;
          expect(contrastRatio(style.activeColor, surface), greaterThanOrEqualTo(3));
          expect(contrastRatio(style.inactiveColor, surface), greaterThanOrEqualTo(3));
          expect(contrastRatio(style.thumbBorderColor, surface), greaterThanOrEqualTo(3));
        });
      }
    });
  }
}
