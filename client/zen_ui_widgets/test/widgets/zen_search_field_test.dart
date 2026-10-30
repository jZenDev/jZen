import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/search/zen_search_field.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show ZenIconButton;

import '../support/a11y.dart';

typedef Build =
    Widget Function(
      BuildContext context, {
      required String label,
      required TextEditingController controller,
      required FocusNode focusNode,
      required String clearLabel,
      required bool enabled,
      required VoidCallback onClear,
      String? hint,
      bool autofocus,
      ValueChanged<String>? onChanged,
      ValueChanged<String>? onSubmitted,
    });

final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialSearchField,
  'cupertino': buildCupertinoSearchField,
};

/// The idiom under test, wired the way [ZenSearchField] wires it.
class Harness {
  Harness(this.build);

  final Build build;
  final TextEditingController controller = TextEditingController();
  final FocusNode focus = FocusNode();
  final List<String> changed = <String>[];
  final List<String> submitted = <String>[];

  Widget widget({bool enabled = true, String label = 'Search accounts', String? hint}) => Column(
    children: <Widget>[
      Builder(
        builder: (BuildContext context) => build(
          context,
          label: label,
          hint: hint,
          controller: controller,
          focusNode: focus,
          clearLabel: 'Clear search',
          enabled: enabled,
          onChanged: changed.add,
          onSubmitted: submitted.add,
          onClear: () {
            controller.clear();
            changed.add('');
            focus.requestFocus();
          },
        ),
      ),
      const TextField(key: Key('after')),
    ],
  );

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

Finder get field => find.byType(EditableText);

void main() {
  testWidgets('the public widget follows the compile-time platform', (tester) async {
    await pumpApp(tester, const ZenSearchField(label: 'Search accounts'));
    expect(find.byType(CupertinoTextField), zenIsApplePlatform ? findsOneWidget : findsNothing);
    expect(find.byType(TextField), zenIsApplePlatform ? findsNothing : findsOneWidget);
  });

  testWidgets('owns a controller it created and leaves one it was given alone', (tester) async {
    final List<String> seen = <String>[];
    await pumpApp(tester, ZenSearchField(label: 'Search accounts', onChanged: seen.add));
    await tester.enterText(field.first, 'rent');
    await tester.pump();
    expect(find.byType(ZenIconButton), findsWidgets);
    await tester.tap(find.byType(ZenIconButton));
    await tester.pump();
    expect(seen, <String>['rent', '']);
    expect(find.text('rent'), findsNothing);

    final TextEditingController mine = TextEditingController(text: 'abc');
    await pumpApp(tester, ZenSearchField(label: 'Search accounts', controller: mine));
    expect(find.text('abc'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    mine.text = 'still usable'; // throws if the field disposed it
    mine.dispose();
  });

  testWidgets('the clear button is named in the app language', (tester) async {
    await pumpApp(
      tester,
      const ZenSearchField(label: 'Пошук рахунків'),
      locale: const Locale('uk'),
    );
    await tester.enterText(field.first, 'оренда');
    await tester.pump();
    expect(find.bySemanticsLabel('Очистити пошук'), findsOneWidget);
  });

  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('the field is named once; empty it offers no clear button', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final Harness h = Harness(entry.value);
        addTearDown(h.dispose);
        await pumpApp(tester, h.widget(hint: 'Name or number'));

        final SemanticsNode node = tester.getSemantics(field.first);
        final SemanticsData data = node.getSemanticsData();
        expect(data.flagsCollection.isTextField, isTrue);
        expect(
          occurrences('${data.label} ${data.hint}', 'Search accounts'),
          lessThanOrEqualTo(1),
          reason: '"${data.label}" / "${data.hint}"',
        );
        expect(
          data.label.contains('Search accounts') || data.hint.contains('Search accounts'),
          isTrue,
        );
        expect(find.byType(ZenIconButton), findsNothing);
        handle.dispose();
      });

      testWidgets('typing reveals a separately named, separately operable clear button', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final Harness h = Harness(entry.value);
        addTearDown(h.dispose);
        await pumpApp(tester, h.widget());
        await tester.enterText(field.first, 'rent');
        await tester.pump();

        final List<SemanticsData> buttons = nodesWith(
          tester,
          SemanticsAction.tap,
        ).where((SemanticsData d) => d.flagsCollection.isButton).toList();
        expect(buttons.where((SemanticsData d) => d.label.contains('Clear search')), hasLength(1));
        final SemanticsData input = tester.getSemantics(field.first).getSemanticsData();
        expect(input.label.contains('Clear search'), isFalse, reason: 'not merged into the field');
        handle.dispose();
      });

      testWidgets('clear empties the field, reports it and keeps focus in the field', (
        tester,
      ) async {
        final Harness h = Harness(entry.value);
        addTearDown(h.dispose);
        await pumpApp(tester, h.widget());
        await tester.enterText(field.first, 'rent');
        await tester.pump();
        await tester.tap(find.byType(ZenIconButton));
        await tester.pumpAndSettle();
        expect(h.controller.text, '');
        expect(h.changed.last, '');
        expect(h.focus.hasFocus, isTrue);
        expect(find.byType(ZenIconButton), findsNothing);
      });

      testWidgets('Escape clears a field that has text and is left alone when empty', (
        tester,
      ) async {
        final Harness h = Harness(entry.value);
        addTearDown(h.dispose);
        final List<LogicalKeyboardKey> reachedOutside = <LogicalKeyboardKey>[];
        await pumpApp(
          tester,
          Focus(
            onKeyEvent: (FocusNode node, KeyEvent event) {
              if (event is KeyDownEvent) reachedOutside.add(event.logicalKey);
              return KeyEventResult.ignored;
            },
            child: h.widget(),
          ),
        );
        h.focus.requestFocus();
        await tester.pump();
        await tester.enterText(field.first, 'rent');
        await tester.pump();
        await press(tester, LogicalKeyboardKey.escape);
        expect(h.controller.text, '');
        expect(reachedOutside, isNot(contains(LogicalKeyboardKey.escape)), reason: 'consumed');

        await press(tester, LogicalKeyboardKey.escape);
        expect(reachedOutside, contains(LogicalKeyboardKey.escape), reason: 'empty: not consumed');
      }, semanticsEnabled: false);

      testWidgets('the search key submits the text', (tester) async {
        final Harness h = Harness(entry.value);
        addTearDown(h.dispose);
        await pumpApp(tester, h.widget());
        await tester.enterText(field.first, 'rent');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        expect(h.submitted, <String>['rent']);
      });

      testWidgets('Tab visits the field, then the clear button, then leaves', (tester) async {
        final Harness h = Harness(entry.value);
        addTearDown(h.dispose);
        await pumpApp(tester, h.widget());
        await tester.enterText(field.first, 'rent');
        await tester.pump();
        h.focus.unfocus();
        await tester.pump();

        await press(tester, LogicalKeyboardKey.tab);
        expect(h.focus.hasFocus, isTrue, reason: 'first stop: the field');
        await press(tester, LogicalKeyboardKey.tab);
        expect(h.focus.hasFocus, isFalse);
        expect(isRinged(tester, find.byType(ZenIconButton)), isTrue, reason: 'the clear button');
        await press(tester, LogicalKeyboardKey.enter);
        expect(h.controller.text, '', reason: 'Enter activates the clear button');
        expect(h.focus.hasFocus, isTrue);
      }, semanticsEnabled: false);

      testWidgets('disabled: keeps its text, takes no input, offers no clear button', (
        tester,
      ) async {
        final Harness h = Harness(entry.value);
        addTearDown(h.dispose);
        h.controller.text = 'rent';
        await pumpApp(tester, h.widget(enabled: false));
        expect(find.text('rent'), findsOneWidget);
        expect(find.byType(ZenIconButton), findsNothing);
        await press(tester, LogicalKeyboardKey.tab);
        expect(h.focus.hasFocus, isFalse);
      });

      testWidgets('a long label and large text fit a narrow screen', (tester) async {
        final Harness h = Harness(entry.value);
        addTearDown(h.dispose);
        h.controller.text = 'rent';
        await pumpApp(
          tester,
          h.widget(label: 'Search accounts, cards and loans by name or number'),
          size: const Size(260, 700),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(field.first).height, greaterThanOrEqualTo(20));
      });

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA text contrast, empty and filled (${theme.key})', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          final Harness h = Harness(entry.value);
          addTearDown(h.dispose);
          await pumpApp(tester, h.widget(hint: 'Name or number'), theme: theme.value);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await tester.enterText(field.first, 'rent');
          await tester.pump();
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    });
  }
}
