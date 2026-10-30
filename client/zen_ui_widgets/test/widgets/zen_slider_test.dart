import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/slider/slider_values.dart';
import 'package:zen_ui_widgets/src/slider/zen_slider.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../support/a11y.dart';

typedef Build =
    Widget Function(
      BuildContext context,
      String label,
      double value,
      double min,
      double max,
      int? divisions,
      String Function(double) format,
      ValueChanged<double>? onChanged,
    );

final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialSlider,
  'cupertino': buildCupertinoSlider,
};

String db(double v) => '${v.round()} dB';

/// A slider the way the public widget frames it (caption included), around the idiom under test.
Widget slider(
  Build build, {
  double value = 40,
  double min = 0,
  double max = 100,
  int? divisions,
  ValueChanged<double>? onChanged,
}) => Builder(
  builder: (BuildContext context) => Column(
    children: <Widget>[
      build(context, 'Volume', value, min, max, divisions, db, onChanged),
      const TextField(key: Key('after')),
    ],
  ),
);

List<SemanticsData> sliders(WidgetTester tester) => nodesWith(tester, SemanticsAction.increase);

/// What a screen reader does: asks the one slider node to step.
void perform(WidgetTester tester, SemanticsAction action) {
  late SemanticsNode found;
  bool visit(SemanticsNode node) {
    if (!node.isMergedIntoParent && node.getSemanticsData().hasAction(action)) found = node;
    node.visitChildren(visit);
    return true;
  }

  visit(rootSemantics(tester));
  tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(found.id, action);
}

void main() {
  group('values', () {
    test('clamp limits a value and sends NaN to the minimum', () {
      expect(zenSliderClamp(120, 0, 100), 100);
      expect(zenSliderClamp(-5, 0, 100), 0);
      expect(zenSliderClamp(double.nan, 10, 100), 10);
      expect(zenSliderClamp(double.infinity, 0, 100), 100);
    });

    test('snap moves to the nearest division and stays in range', () {
      expect(zenSliderSnap(37, 0, 100, 10), 40);
      expect(zenSliderSnap(36, 0, 100, 10), 40);
      expect(zenSliderSnap(34, 0, 100, 10), 30);
      expect(zenSliderSnap(500, 0, 100, 10), 100);
      expect(zenSliderSnap(37.5, 0, 100, null), 37.5);
    });

    test('bounds must be finite, ordered, with positive divisions', () {
      expect(zenSliderBoundsAreValid(0, 1, null), isTrue);
      expect(zenSliderBoundsAreValid(1, 1, null), isFalse);
      expect(zenSliderBoundsAreValid(2, 1, null), isFalse);
      expect(zenSliderBoundsAreValid(double.nan, 1, null), isFalse);
      expect(zenSliderBoundsAreValid(0, double.infinity, null), isFalse);
      expect(zenSliderBoundsAreValid(0, 1, 0), isFalse);
    });

    test('keys: arrows follow the track, pages and ends jump', () {
      double? key(LogicalKeyboardKey k, {bool rtl = false, double value = 40}) =>
          zenSliderKeyTarget(
            k,
            value: value,
            lowest: 0,
            highest: 100,
            min: 0,
            max: 100,
            divisions: null,
            rtl: rtl,
          );
      expect(key(LogicalKeyboardKey.arrowRight), 50);
      expect(key(LogicalKeyboardKey.arrowLeft), 30);
      expect(key(LogicalKeyboardKey.arrowRight, rtl: true), 30);
      expect(key(LogicalKeyboardKey.arrowUp), 50);
      expect(key(LogicalKeyboardKey.pageUp), 65);
      expect(key(LogicalKeyboardKey.home), 0);
      expect(key(LogicalKeyboardKey.end), 100);
      expect(key(LogicalKeyboardKey.arrowRight, value: 100), 100);
      expect(key(LogicalKeyboardKey.keyA), isNull);
    });
  });

  testWidgets('the public widget follows the compile-time platform', (tester) async {
    await pumpApp(
      tester,
      ZenSlider(label: 'Volume', value: 40, min: 0, max: 100, onChanged: (_) {}),
    );
    expect(find.byType(Slider), zenIsApplePlatform ? findsNothing : findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
  });

  testWidgets('shows the app-formatted value beside the label', (tester) async {
    await pumpApp(
      tester,
      ZenSlider(
        label: 'Volume',
        value: 40,
        min: 0,
        max: 100,
        valueFormatter: db,
        onChanged: (_) {},
      ),
    );
    expect(find.text('40 dB'), findsOneWidget);
  });

  testWidgets('a value outside the range is shown at the nearest end, not reported', (
    tester,
  ) async {
    final List<double> seen = <double>[];
    await pumpApp(
      tester,
      ZenSlider(label: 'Volume', value: 500, min: 0, max: 100, onChanged: seen.add),
    );
    expect(find.text('100'), findsOneWidget);
    expect(seen, isEmpty);
  });

  test('invalid bounds are rejected', () {
    expect(
      () => ZenSlider(label: 'Volume', value: 1, min: 5, max: 5, onChanged: (_) {}),
      throwsAssertionError,
    );
    expect(
      () => ZenSlider(label: 'Volume', value: 1, min: 0, max: 5, divisions: 0, onChanged: (_) {}),
      throwsAssertionError,
    );
  });

  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('is one slider: name, value, range actions, announced once', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, slider(entry.value, divisions: 10, onChanged: (_) {}));

        final List<SemanticsData> nodes = sliders(tester);
        expect(nodes, hasLength(1), reason: nodes.map((n) => n.label).join(' | '));
        final SemanticsData data = nodes.single;
        expect(occurrences(data.label, 'Volume'), 1, reason: data.label);
        expect(data.value, '40 dB');
        expect(data.increasedValue, '50 dB');
        expect(data.decreasedValue, '30 dB');
        expect(data.flagsCollection.isSlider, isTrue);
        expect(isEnabled(data), isTrue);
        handle.dispose();
      });

      testWidgets('the screen reader increments and decrements one step', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final List<double> seen = <double>[];
        await pumpApp(tester, slider(entry.value, onChanged: seen.add, divisions: 20));
        perform(tester, SemanticsAction.increase);
        perform(tester, SemanticsAction.decrease);
        expect(seen, <double>[45, 35]);
        handle.dispose();
      });

      testWidgets('with divisions it reports only its steps', (tester) async {
        final List<double> seen = <double>[];
        await pumpApp(tester, slider(entry.value, onChanged: seen.add, divisions: 10));
        await tester.drag(find.byType(FocusRing), const Offset(97, 0));
        await tester.pumpAndSettle();
        expect(seen, isNotEmpty);
        for (final double v in seen) {
          expect(v % 10, closeTo(0, 1e-9), reason: '$v is not on a division');
          expect(v, inInclusiveRange(0, 100));
        }
      });

      testWidgets('Tab reaches it, arrows, Page and ends move it, and a ring shows', (
        tester,
      ) async {
        double value = 40;
        await pumpApp(
          tester,
          StatefulBuilder(
            builder: (BuildContext context, StateSetter set) =>
                slider(entry.value, value: value, onChanged: (double v) => set(() => value = v)),
          ),
        );
        expect(isRinged(tester, find.byType(FocusRing)), isFalse);
        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing)), isTrue);

        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(value, greaterThan(40));
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(value, closeTo(40, 1e-9));

        await press(tester, LogicalKeyboardKey.home);
        expect(value, 0);
        await press(tester, LogicalKeyboardKey.end);
        expect(value, 100);
        await press(tester, LogicalKeyboardKey.pageDown);
        expect(value, lessThan(100));
        await press(tester, LogicalKeyboardKey.arrowRight);
        await press(tester, LogicalKeyboardKey.end);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(value, 100, reason: 'never past the maximum');
      }, semanticsEnabled: false);

      testWidgets('exactly one tab stop', (tester) async {
        await pumpApp(tester, slider(entry.value, onChanged: (_) {}));
        await press(tester, LogicalKeyboardKey.tab);
        await press(tester, LogicalKeyboardKey.tab);
        expect(
          FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>(),
          isNotNull,
        );
      });

      testWidgets('disabled: no range actions, announced as disabled, not focusable', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, slider(entry.value));
        expect(sliders(tester), isEmpty);
        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing)), isFalse);
        handle.dispose();
      });

      testWidgets('is at least 48 logical pixels tall and fits a narrow, scaled screen', (
        tester,
      ) async {
        await pumpApp(
          tester,
          slider(entry.value, onChanged: (_) {}),
          size: const Size(220, 700),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(FocusRing)).height, greaterThanOrEqualTo(48));
      });

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA text contrast (${theme.key})', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpApp(tester, slider(entry.value, onChanged: (_) {}), theme: theme.value);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    });
  }
}
