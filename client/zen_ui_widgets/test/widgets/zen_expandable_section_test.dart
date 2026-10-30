import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/expandable/zen_expandable_body.dart';
import 'package:zen_ui_widgets/src/expandable/zen_expandable_section.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../support/a11y.dart';

typedef Build =
    Widget Function(
      BuildContext context,
      String title,
      String? subtitle,
      bool expanded,
      ValueChanged<bool>? onChanged,
      bool maintainState,
      Widget child,
    );

final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialExpandableSection,
  'cupertino': buildCupertinoExpandableSection,
};

/// A section whose state lives in the test, with a text field inside it and one after it.
class Harness {
  Harness(this.build, {this.expanded = false, this.maintainState = false, this.enabled = true});

  final Build build;
  bool expanded;
  final bool maintainState;
  final bool enabled;
  final List<bool> asked = <bool>[];

  Widget widget({String title = 'Advanced options', String? subtitle}) => StatefulBuilder(
    builder: (BuildContext context, StateSetter set) => Column(
      children: <Widget>[
        build(
          context,
          title,
          subtitle,
          expanded,
          enabled
              ? (bool next) {
                  asked.add(next);
                  set(() => expanded = next);
                }
              : null,
          maintainState,
          const TextField(key: Key('inside')),
        ),
        const TextField(key: Key('after')),
      ],
    ),
  );
}

Finder get inside => find.byKey(const Key('inside'));

void main() {
  testWidgets('the public widget follows the compile-time platform', (tester) async {
    await pumpApp(
      tester,
      ZenExpandableSection(
        title: 'Advanced options',
        expanded: true,
        onChanged: (_) {},
        child: const Text('Body'),
      ),
    );
    expect(find.byType(ListTile), zenIsApplePlatform ? findsNothing : findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
  });

  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('the header is one named button with its expanded state', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final Harness h = Harness(entry.value);
        await pumpApp(tester, h.widget(subtitle: 'Rarely needed'));

        SemanticsData header() => nodesWith(
          tester,
          SemanticsAction.tap,
        ).firstWhere((SemanticsData d) => d.label.contains('Advanced options'));
        expect(occurrences(header().label, 'Advanced options'), 1, reason: header().label);
        expect('${header().label} ${header().hint}', contains('Rarely needed'));
        expect(header().flagsCollection.isExpanded, Tristate.isFalse);
        expect(isEnabled(header()), isTrue);

        await tester.tap(find.text('Advanced options'));
        await tester.pumpAndSettle();
        expect(header().flagsCollection.isExpanded, Tristate.isTrue);
        handle.dispose();
      });

      testWidgets('a tap asks for the opposite value; the app decides', (tester) async {
        final Harness h = Harness(entry.value);
        await pumpApp(tester, h.widget());
        expect(inside, findsNothing);
        await tester.tap(find.text('Advanced options'));
        await tester.pumpAndSettle();
        expect(h.asked, <bool>[true]);
        expect(inside, findsOneWidget);
        await tester.tap(find.text('Advanced options'));
        await tester.pumpAndSettle();
        expect(h.asked, <bool>[true, false]);
        expect(inside, findsNothing);
      });

      testWidgets('collapsed content is discarded; its state starts fresh on reopening', (
        tester,
      ) async {
        final Harness h = Harness(entry.value, expanded: true);
        await pumpApp(tester, h.widget());
        await tester.enterText(inside, 'draft');
        await tester.tap(find.text('Advanced options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Advanced options'));
        await tester.pumpAndSettle();
        expect(find.text('draft'), findsNothing);
      });

      testWidgets('maintainState keeps the content, unreachable while collapsed', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final Harness h = Harness(entry.value, expanded: true, maintainState: true);
        await pumpApp(tester, h.widget());
        await tester.enterText(inside, 'draft');
        await tester.tap(find.text('Advanced options'));
        await tester.pumpAndSettle();

        // Mounted, but not painted, not hit-testable, not focusable and not read.
        expect(inside.hitTestable(), findsNothing);
        expect(
          find.byKey(const Key('inside'), skipOffstage: false),
          findsOneWidget,
          reason: 'state kept',
        );
        expect(find.text('draft', skipOffstage: false), findsOneWidget);
        expect(find.text('draft'), findsNothing, reason: 'offstage');
        expect(
          nodesWith(
            tester,
            SemanticsAction.tap,
          ).where((SemanticsData d) => d.flagsCollection.isTextField),
          hasLength(1),
          reason: 'only the field after the section is read',
        );

        await tester.tap(find.text('Advanced options'));
        await tester.pumpAndSettle();
        expect(find.text('draft'), findsOneWidget, reason: 'state survived');
        handle.dispose();
      });

      testWidgets('collapsed content is not a tab stop and not announced; expanded it is', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final Harness h = Harness(entry.value, maintainState: true);
        await pumpApp(tester, h.widget());

        await press(tester, LogicalKeyboardKey.tab); // header
        await press(tester, LogicalKeyboardKey.tab); // straight past the collapsed content
        expect(FocusManager.instance.primaryFocus?.context?.widget.key, isNot(const Key('inside')));
        final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
        expect(focused?.findAncestorWidgetOfExactType<TextField>()?.key, const Key('after'));

        h.expanded = true;
        FocusManager.instance.primaryFocus?.unfocus();
        await pumpApp(tester, h.widget());
        await press(tester, LogicalKeyboardKey.tab);
        await press(tester, LogicalKeyboardKey.tab);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<TextField>()
              ?.key,
          const Key('inside'),
        );
        handle.dispose();
      }, semanticsEnabled: false);

      testWidgets('Tab reaches the header, Space and Enter toggle it, and a ring shows', (
        tester,
      ) async {
        final Harness h = Harness(entry.value);
        await pumpApp(tester, h.widget());
        expect(isRinged(tester, find.byType(FocusRing).first), isFalse);
        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing).first), isTrue);
        await press(tester, LogicalKeyboardKey.space);
        expect(h.asked, <bool>[true]);
        await press(tester, LogicalKeyboardKey.enter);
        expect(h.asked, <bool>[true, false]);
      }, semanticsEnabled: false);

      testWidgets('disabled: readable, no tap action, not focusable, content unchanged', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final Harness h = Harness(entry.value, expanded: true, enabled: false);
        await pumpApp(tester, h.widget());
        expect(inside, findsOneWidget, reason: 'stays as the app has it');
        final SemanticsData header = tester
            .getSemantics(find.text('Advanced options'))
            .getSemanticsData();
        expect(isEnabled(header), isFalse);
        expect(header.hasAction(SemanticsAction.tap), isFalse);
        await tester.tap(find.text('Advanced options'));
        await tester.pumpAndSettle();
        expect(h.asked, isEmpty);
        expect(inside, findsOneWidget);
        handle.dispose();
      });

      testWidgets('animates open, and instantly when the system asks for reduced motion', (
        tester,
      ) async {
        final Harness h = Harness(entry.value);
        await pumpApp(tester, h.widget());
        await tester.tap(find.text('Advanced options'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final double partway = tester.getSize(find.byType(ZenExpandableBody)).height;
        await tester.pumpAndSettle();
        final double full = tester.getSize(find.byType(ZenExpandableBody)).height;
        expect(partway, lessThan(full), reason: 'still growing after 60 ms');

        tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
          disableAnimations: true,
        );
        addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await pumpApp(tester, h.widget());
        await tester.tap(find.text('Advanced options'));
        await tester.pump();
        expect(inside, findsNothing, reason: 'collapsed in a single frame');
        await tester.tap(find.text('Advanced options'));
        await tester.pump();
        expect(
          tester.getSize(find.byType(ZenExpandableBody)).height,
          full,
          reason: 'opened in a single frame',
        );
      });

      testWidgets('a long title and 200% text reflow on a narrow screen', (tester) async {
        final Harness h = Harness(entry.value, expanded: true);
        await pumpApp(
          tester,
          h.widget(
            title: 'Advanced options for people who need to change many of the defaults',
            subtitle: 'Rarely needed, and safe to leave alone for almost everybody',
          ),
          size: const Size(260, 900),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(FocusRing).first).height, greaterThanOrEqualTo(48));
      });

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA text contrast (${theme.key})', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          final Harness h = Harness(entry.value, expanded: true);
          await pumpApp(tester, h.widget(subtitle: 'Rarely needed'), theme: theme.value);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }

      if (entry.key == 'cupertino') {
        testWidgets('does not paint a Material splash or highlight', (tester) async {
          final Harness h = Harness(entry.value);
          await pumpApp(tester, h.widget());
          final InkWell ink = tester.widget<InkWell>(find.byType(InkWell));
          expect(ink.splashFactory, NoSplash.splashFactory);
          expect(ink.highlightColor, Colors.transparent);
        });
      }
    });
  }
}
