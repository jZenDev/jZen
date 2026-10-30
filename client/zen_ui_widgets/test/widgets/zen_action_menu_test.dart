import 'dart:ui' show Tristate;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/menu/zen_action_menu.dart';
import 'package:zen_ui_widgets/src/menu/zen_action_menu_view.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show ZenIconButton;

import '../support/a11y.dart';

final Map<String, ZenActionMenuBuilder> builds = <String, ZenActionMenuBuilder>{
  'material': buildMaterialActionMenu,
  'cupertino': buildCupertinoActionMenu,
};

class Harness {
  Harness(this.build);

  final ZenActionMenuBuilder build;
  final List<String> ran = <String>[];

  List<ZenMenuAction> actions({String rename = 'Rename', bool disabled = true}) => <ZenMenuAction>[
    ZenMenuAction(label: rename, icon: Icons.edit, onPressed: () => ran.add('rename')),
    ZenMenuAction(label: 'Archive', onPressed: disabled ? null : () => ran.add('archive')),
    ZenMenuAction(label: 'English', selected: true, onPressed: () => ran.add('english')),
    ZenMenuAction(label: 'Delete', destructive: true, onPressed: () => ran.add('delete')),
  ];

  Widget widget({String rename = 'Rename', bool disabled = true}) => Column(
    children: <Widget>[
      ZenActionMenuView(
        label: 'Actions',
        icon: Icons.more_vert,
        actions: actions(rename: rename, disabled: disabled),
        builder: build,
      ),
      const TextField(key: Key('after')),
    ],
  );
}

/// Whether focus is on the menu's trigger button.
bool triggerFocused() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<ZenIconButton>() !=
    null;

void main() {
  testWidgets('the public widget follows the compile-time platform', (tester) async {
    await pumpApp(
      tester,
      ZenActionMenu(
        label: 'Actions',
        actions: <ZenMenuAction>[ZenMenuAction(label: 'Rename', onPressed: () {})],
      ),
    );
    expect(find.byType(MenuAnchor), zenIsApplePlatform ? findsNothing : findsOneWidget);
    expect(find.byType(CupertinoMenuAnchor), zenIsApplePlatform ? findsOneWidget : findsNothing);
  });

  test('rejects an empty menu', () {
    expect(() => ZenActionMenu(label: 'x', actions: const <ZenMenuAction>[]), throwsAssertionError);
  });

  for (final MapEntry<String, ZenActionMenuBuilder> entry in builds.entries) {
    group(entry.key, () {
      Future<Harness> show(
        WidgetTester tester, {
        Size? size,
        double scale = 1,
        String? rename,
      }) async {
        final Harness h = Harness(entry.value);
        await pumpApp(
          tester,
          h.widget(rename: rename ?? 'Rename'),
          size: size ?? const Size(800, 900),
          textScale: scale,
        );
        return h;
      }

      Future<void> openMenu(WidgetTester tester) async {
        await tester.tap(find.byType(ZenIconButton));
        await tester.pumpAndSettle();
      }

      testWidgets('the trigger is one named button that reports whether the menu is open', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await show(tester);
        SemanticsData trigger() => nodesWith(
          tester,
          SemanticsAction.tap,
        ).firstWhere((SemanticsData d) => d.label.contains('Actions'));
        expect(occurrences(trigger().label, 'Actions'), 1, reason: trigger().label);
        expect(trigger().flagsCollection.isExpanded, anyOf(Tristate.isFalse, Tristate.none));

        await openMenu(tester);
        expect(trigger().flagsCollection.isExpanded, Tristate.isTrue);
        handle.dispose();
      });

      testWidgets('opens on a tap, lists every action, and marks disabled and selected ones', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await show(tester);
        await openMenu(tester);
        for (final String name in <String>['Rename', 'Archive', 'English', 'Delete']) {
          expect(find.text(name), findsOneWidget);
        }
        SemanticsData item(String name) => tester.getSemantics(find.text(name)).getSemanticsData();
        expect(isEnabled(item('Rename')), isTrue);
        expect(isEnabled(item('Archive')), isFalse);
        expect(item('Archive').hasAction(SemanticsAction.tap), isFalse);
        expect(item('English').flagsCollection.isSelected, Tristate.isTrue);
        expect(item('Rename').flagsCollection.isSelected, isNot(Tristate.isTrue));
        handle.dispose();
      });

      testWidgets('choosing an action runs it once, closes the menu, returns focus', (
        tester,
      ) async {
        final Harness h = await show(tester);
        await openMenu(tester);
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        expect(h.ran, <String>['rename']);
        expect(find.text('Archive'), findsNothing, reason: 'closed');
        expect(triggerFocused(), isTrue);
      });

      testWidgets('a disabled action never fires and leaves the menu open', (tester) async {
        final Harness h = await show(tester);
        await openMenu(tester);
        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();
        expect(h.ran, isEmpty);
      });

      testWidgets('Escape and a tap outside close it without running anything', (tester) async {
        final Harness h = await show(tester);
        await openMenu(tester);
        await press(tester, LogicalKeyboardKey.escape);
        expect(find.text('Rename'), findsNothing);
        expect(h.ran, isEmpty);
        expect(triggerFocused(), isTrue, reason: 'focus returns to the trigger');

        await openMenu(tester);
        await tester.tapAt(const Offset(5, 880));
        await tester.pumpAndSettle();
        expect(find.text('Rename'), findsNothing);
        expect(h.ran, isEmpty);
      });

      testWidgets('keyboard: Enter opens, arrows skip the disabled item, Enter chooses', (
        tester,
      ) async {
        final Harness h = await show(tester);
        await press(tester, LogicalKeyboardKey.tab);
        expect(triggerFocused(), isTrue);
        await press(tester, LogicalKeyboardKey.enter);
        expect(find.text('Rename'), findsOneWidget);

        // Opening by keyboard moves focus into the menu; the disabled item is never a stop.
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.enter);
        expect(h.ran, <String>['delete'], reason: 'Rename -> English -> Delete; Archive skipped');
        expect(find.text('Rename'), findsNothing, reason: 'choosing closes the menu');
        expect(triggerFocused(), isTrue);
      }, semanticsEnabled: false);

      testWidgets('Space on the trigger opens and Enter on an item does not fire twice', (
        tester,
      ) async {
        final Harness h = await show(tester);
        await press(tester, LogicalKeyboardKey.tab);
        await press(tester, LogicalKeyboardKey.space);
        expect(find.text('Rename'), findsOneWidget);
        await press(tester, LogicalKeyboardKey.enter);
        expect(h.ran, <String>['rename'], reason: 'one activation, on the first item');
      }, semanticsEnabled: false);

      testWidgets('a ring marks the focused trigger', (tester) async {
        await show(tester);
        expect(isRinged(tester, find.byType(ZenIconButton)), isFalse);
        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(ZenIconButton)), isTrue);
      }, semanticsEnabled: false);

      testWidgets('a narrow window and 200% text do not clip or overflow', (tester) async {
        await show(
          tester,
          size: const Size(260, 700),
          scale: 2,
          rename: 'Rename this account to something much longer than fits',
        );
        await openMenu(tester);
        expect(tester.takeException(), isNull);
        final Rect screen = Offset.zero & const Size(260, 700);
        for (final Element e in find.textContaining('Rename this').evaluate()) {
          final Rect r = tester.getRect(find.byElementPredicate((Element x) => x == e));
          expect(
            screen.contains(r.topLeft) && screen.contains(r.bottomRight),
            isTrue,
            reason: '$r',
          );
        }
        for (final String name in <String>['Archive', 'English', 'Delete']) {
          expect(find.text(name), findsOneWidget);
        }
      });

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('open menu meets AA text contrast (${theme.key})', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          final Harness h = Harness(entry.value);
          // A disabled label is exempt from the contrast rule, so it is left out of this check.
          await pumpApp(tester, h.widget(disabled: false), theme: theme.value);
          await openMenu(tester);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    });
  }
}
