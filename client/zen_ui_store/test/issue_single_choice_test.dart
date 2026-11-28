import 'dart:ui' show CheckedState, SemanticsRole;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_store/zen_ui_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'support/conflict_fixture.dart';

/// How many candidates a choice action has is the application's data, so there may be only one.
void main() {
  late List<String> chosen;
  late int done;

  Widget screen() => conflictApp(
    home: ZenIssueScreen(
      issue: ZenIssue(
        id: 'ask',
        title: 'Record has no account',
        description: 'Its account was deleted elsewhere.',
        actions: [
          ZenIssueAction.choose(
            label: 'Move to account',
            choices: [('only', 'Savings')],
            run: (id) async {
              chosen.add(id);
              return const ZenResult.ok(null);
            },
          ),
        ],
      ),
      onDone: () => done++,
    ),
  );

  Future<void> openPrompt(WidgetTester tester) async {
    chosen = [];
    done = 0;
    await tester.pumpWidget(screen());
    await tester.tap(find.text('Move to account'));
    await tester.pumpAndSettle();
  }

  bool continueEnabled(WidgetTester tester) =>
      tester.widget<ZenButton>(find.widgetWithText(ZenButton, 'Continue')).onPressed != null;

  testWidgets('the one candidate is shown and nothing is chosen for the person', (tester) async {
    await openPrompt(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Savings'), findsOneWidget);
    expect(continueEnabled(tester), isFalse);
    expect(chosen, isEmpty);
  });

  testWidgets('choosing it and continuing runs once with its id', (tester) async {
    await openPrompt(tester);
    await tester.tap(find.text('Savings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(chosen, ['only']);
    expect(done, 1);
  });

  testWidgets('cancelling runs nothing, even after choosing', (tester) async {
    await openPrompt(tester);
    await tester.tap(find.text('Savings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(chosen, isEmpty);
    expect(done, 0);
    expect(find.text('Savings'), findsNothing);
    expect(find.text('Move to account'), findsOneWidget);
  });

  testWidgets('a screen reader hears one radio in a named group', (tester) async {
    final handle = tester.ensureSemantics();
    await openPrompt(tester);

    final radio = find.semantics.byPredicate(
      (node) =>
          !node.isMergedIntoParent &&
          node.getSemanticsData().flagsCollection.isInMutuallyExclusiveGroup,
      describeMatch: (_) => 'radio',
    );
    expect(radio, findsOne);
    SemanticsData data() => radio.evaluate().single.getSemanticsData();
    expect(data().label, 'Savings');
    expect(data().flagsCollection.isChecked, CheckedState.isFalse);
    expect(data().hasAction(SemanticsAction.tap), isTrue);

    final ancestors = <SemanticsNode>[
      for (var node = radio.evaluate().single.parent; node != null; node = node.parent) node,
    ];
    expect(ancestors.map((node) => node.role), contains(SemanticsRole.radioGroup));
    expect(ancestors.map((node) => node.label), contains('Move to account'), reason: 'group name');

    await tester.tap(find.text('Savings'));
    await tester.pumpAndSettle();
    expect(data().flagsCollection.isChecked, CheckedState.isTrue);

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  test('a choice with no candidate is refused where it is built', () {
    expect(
      () => ZenIssueAction.choose(
        label: 'Move to account',
        choices: <(String, String)>[],
        run: (_) async => const ZenResult.ok(null),
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
