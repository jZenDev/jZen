import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/zen_progress_bar.dart';

import '../support/a11y.dart';

typedef Build = Widget Function(BuildContext context, double fraction, Color? color);

/// Both idioms are built directly: the public widget chooses one on a compile-time constant, so
/// one run only reaches the branch of the host it was compiled for.
final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialProgressBar,
  'cupertino': buildCupertinoProgressBar,
};

/// Fills the bar's width: [ZenProgressBar] has none of its own, as in a list row.
Widget bar(Build build, double fraction, {Color? color}) => SizedBox(
  width: 200,
  child: Builder(builder: (BuildContext context) => build(context, fraction, color)),
);

void main() {
  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('draws the fraction of the track', (tester) async {
        await pumpApp(tester, Center(child: bar(entry.value, 0.25)), settle: false);
        expect(tester.getSize(find.byType(SizedBox).first).width, 200);
        if (entry.key == 'cupertino') {
          final Size fill = tester.getSize(find.byType(FractionallySizedBox));
          expect(fill.width, 50);
        } else {
          expect(
            tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
            0.25,
          );
        }
      });
    });
  }

  testWidgets('is one node: the label with the value as a percentage', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(
      tester,
      const SizedBox(width: 200, child: ZenProgressBar(value: 0.45, label: 'Groceries')),
      settle: false,
    );

    final List<SemanticsData> found = <SemanticsData>[];
    bool visit(SemanticsNode node) {
      final SemanticsData data = node.getSemanticsData();
      if (!node.isMergedIntoParent && (data.label.isNotEmpty || data.value.isNotEmpty)) {
        found.add(data);
      }
      node.visitChildren(visit);
      return true;
    }

    visit(rootSemantics(tester));
    expect(found, hasLength(1), reason: found.map((d) => '${d.label}/${d.value}').join(' | '));
    expect(found.single.label, 'Groceries');
    expect(found.single.value, '45%');
    handle.dispose();
  });

  testWidgets('the percentage is written for the locale', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(
      tester,
      const SizedBox(width: 200, child: ZenProgressBar(value: 0.5, label: 'Цілі')),
      locale: const Locale('uk'),
      settle: false,
    );
    final SemanticsNode node = tester.getSemantics(find.byType(ZenProgressBar));
    expect(node.value, isNot('0.5'));
    expect(node.value, contains('50'));
    handle.dispose();
  });

  testWidgets('a value outside 0..1 or not a number draws a full, an empty or an empty bar', (
    tester,
  ) async {
    for (final (double, double) c in <(double, double)>[(1.7, 1), (-0.2, 0), (double.nan, 0)]) {
      await pumpApp(
        tester,
        SizedBox(
          width: 200,
          child: ZenProgressBar(value: c.$1, label: 'x'),
        ),
        settle: false,
      );
      expect(tester.takeException(), isNull);
      final Finder fraction = find.byType(FractionallySizedBox);
      final Finder linear = find.byType(LinearProgressIndicator);
      final double drawn = fraction.evaluate().isNotEmpty
          ? tester.widget<FractionallySizedBox>(fraction).widthFactor!
          : tester.widget<LinearProgressIndicator>(linear).value!;
      expect(drawn, c.$2);
    }
  });

  for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
    testWidgets('the fill meets 3:1 non-text contrast (${theme.key})', (tester) async {
      await pumpApp(
        tester,
        const SizedBox(width: 200, child: ZenProgressBar(value: 0.5, label: 'x')),
        theme: theme.value,
        settle: false,
      );
      final ColorScheme scheme = theme.value.colorScheme;
      expect(contrastRatio(scheme.primary, scheme.surface), greaterThanOrEqualTo(3));
    });
  }

  testWidgets('stays usable at 200% text on a narrow screen', (tester) async {
    await pumpApp(
      tester,
      const ZenProgressBar(value: 0.5, label: 'A rather long goal name that cannot fit'),
      size: const Size(260, 700),
      textScale: 2,
      settle: false,
    );
    expect(tester.takeException(), isNull);
  });
}
