import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

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

/// The root of the semantics tree the test view hands to assistive technology.
SemanticsNode rootSemantics(WidgetTester tester) =>
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;

/// Every node a screen-reader user can land on, after merging, that offers [action] — one entry
/// per thing the user hears as a control.
List<SemanticsData> nodesWith(WidgetTester tester, SemanticsAction action) {
  final List<SemanticsData> found = <SemanticsData>[];
  bool visit(SemanticsNode node) {
    if (!node.isMergedIntoParent) {
      final SemanticsData data = node.getSemanticsData();
      if (data.hasAction(action)) found.add(data);
    }
    node.visitChildren(visit);
    return true;
  }

  visit(rootSemantics(tester));
  return found;
}

/// Whether [data] is enabled: the flag is tri-state, and a node that says nothing about it is
/// neither enabled nor disabled.
bool isEnabled(SemanticsData data) => data.flagsCollection.isEnabled == Tristate.isTrue;

/// Number of non-overlapping occurrences of [needle] in [haystack].
int occurrences(String haystack, String needle) => needle.allMatches(haystack).length;

/// Pumps [child] in a real `MaterialApp` with this package's strings, at [size], [textScale] and
/// [locale]. Sets the test view's own size rather than wrapping in a `MediaQuery`, which
/// `MaterialApp` would replace.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(800, 900),
  ThemeData? theme,
  double textScale = 1,
  Locale? locale,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      locale: locale,
      localizationsDelegates: ZenWidgetsLocalizations.localizationsDelegates,
      supportedLocales: ZenWidgetsLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    ),
  );
  // A spinner never settles; a test that shows one passes settle: false.
  await (settle ? tester.pumpAndSettle() : tester.pump());
}

/// Presses and releases [key], optionally with Shift held, and settles.
Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

/// Whether any [FocusRing] under [of] is currently drawing its outline.
bool isRinged(WidgetTester tester, Finder of) => find
    .descendant(
      of: of,
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border != null &&
            (w.decoration as BoxDecoration).border!.top.width == zenFocusRingWidth,
      ),
    )
    .evaluate()
    .isNotEmpty;
