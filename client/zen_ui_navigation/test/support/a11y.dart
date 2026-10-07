import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

/// Helpers for the accessibility suites. They read what assistive technology reads — the final,
/// merged semantics tree — rather than the widget tree, because a widget test that finds a
/// `Semantics(label: ...)` widget says nothing about what a screen reader announces.

/// WCAG 2.x contrast ratio between two opaque colours, 1.0 (none) to 21.0 (black on white).
double contrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The themes every contrast check runs against: Flutter's default Material 3 palette and a
/// seeded one (the shape a jZen app supplies), each in light and dark.
final Map<String, ThemeData> auditThemes = <String, ThemeData>{
  'default light': ThemeData(brightness: Brightness.light),
  'default dark': ThemeData(brightness: Brightness.dark),
  'seeded light': ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
  'seeded dark': ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
  ),
};

/// Every node a screen-reader user can land on and activate, after merging — one entry per thing
/// the user hears as a control.
List<SemanticsData> actionableNodes(WidgetTester tester) {
  final List<SemanticsData> found = <SemanticsData>[];
  bool visit(SemanticsNode node) {
    if (!node.isMergedIntoParent) {
      final SemanticsData data = node.getSemanticsData();
      if (data.hasAction(SemanticsAction.tap)) found.add(data);
    }
    node.visitChildren(visit);
    return true;
  }

  visit(rootSemantics(tester));
  return found;
}

/// The root of the semantics tree the test view hands to assistive technology.
SemanticsNode rootSemantics(WidgetTester tester) =>
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;

/// Number of non-overlapping occurrences of [needle] in [haystack].
int occurrences(String haystack, String needle) => needle.allMatches(haystack).length;

/// Pumps a navigation layout at [size] in a real `MaterialApp`, with this package's strings.
///
/// Sets the test view's own size rather than wrapping the app in a `MediaQuery`: `MaterialApp`
/// installs its own `MediaQuery` from the view, so an outer one never reaches the layout.
Future<void> pumpNavigation(
  WidgetTester tester,
  Widget Function(BuildContext context) build, {
  Size size = const Size(1200, 800),
  ThemeData? theme,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      home: Builder(builder: build),
    ),
  );
  await tester.pumpAndSettle();
}

/// Three destinations, the last with a badge, each page a distinct text.
List<ZenNavigationItem> auditItems({int count = 3}) => <ZenNavigationItem>[
  for (int i = 0; i < count; i++)
    ZenNavigationItem(
      id: 'id_$i',
      label: 'Item $i',
      icon: Icons.circle,
      badgeCount: i == count - 1 ? 4 : null,
      builder: (_) => Text('page_$i'),
    ),
];

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
