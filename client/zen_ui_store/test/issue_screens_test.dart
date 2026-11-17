import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_store/zen_ui_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'support/conflict_fixture.dart';

/// An application's own cross-record issues, shown beside the store's conflicts. The issue is a
/// stand-in for a rule the application re-checks after a sync (a goal below zero).
void main() {
  late ConflictFixture fixture;
  late bool broken;
  late int fixed;
  ZenResult<Object?> outcome = const ZenResult.ok(null);

  tearDown(() async => fixture.dispose());

  ZenIssueSource issues() => ZenIssueSource(
    issues: () => broken
        ? [
            ZenIssue(
              id: 'goal-1',
              title: 'Holiday goal is below zero',
              description: 'Two withdrawals on two devices took it to -20.',
              actions: [
                ZenIssueAction(
                  label: 'Set it to zero',
                  run: () async {
                    fixed++;
                    if (outcome.isSuccess) broken = false;
                    return outcome;
                  },
                ),
              ],
            ),
          ]
        : const [],
  );

  Future<void> setUp0(WidgetTester tester, {bool withConflict = true}) async {
    broken = true;
    fixed = 0;
    outcome = const ZenResult.ok(null);
    fixture = (await tester.runAsync(ConflictFixture.create))!;
    if (!withConflict) await tester.runAsync(() => fixture.items(fixture.phone).resolve('1', null));
  }

  Widget app({bool withSources = true}) => conflictApp(
    home: Scaffold(
      body: Column(
        children: [
          ZenConflictBanner(
            store: fixture.phone,
            sources: withSources ? [fixture.source(fixture.phone)] : const [],
            issues: [issues()],
          ),
          const Text('main screen'),
        ],
      ),
    ),
  );

  testWidgets('an issue counts in the banner with the store\'s conflicts', (tester) async {
    await setUp0(tester);
    await tester.pumpWidget(app());
    expect(find.text('2 items need your choice.'), findsOneWidget);
  });

  testWidgets('an issue alone raises the banner', (tester) async {
    await setUp0(tester, withConflict: false);
    await tester.pumpWidget(app());
    expect(find.text('1 item needs your choice.'), findsOneWidget);
  });

  testWidgets('the list shows the issue beside the conflict, and the action settles it', (
    tester,
  ) async {
    await setUp0(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Holiday goal is below zero'), findsOneWidget);

    await tester.tap(find.text('Holiday goal is below zero'));
    await tester.pumpAndSettle();
    expect(find.text('Two withdrawals on two devices took it to -20.'), findsOneWidget);
    await tester.tap(find.text('Set it to zero'));
    await tester.pumpAndSettle();

    expect(fixed, 1);
    expect(find.text('Holiday goal is below zero'), findsNothing);
    expect(find.text('Groceries'), findsOneWidget);
  });

  testWidgets('a failed action says so and keeps the issue', (tester) async {
    await setUp0(tester);
    outcome = const ZenResult.err(ZenValidationError('The goal is locked.'));
    await tester.pumpWidget(app());
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Holiday goal is below zero'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set it to zero'));
    await tester.pumpAndSettle();

    expect(find.text('Couldn\'t do that: The goal is locked.'), findsOneWidget);
    expect(find.text('Set it to zero'), findsOneWidget);
  });

  testWidgets('the Ukrainian strings are used', (tester) async {
    await setUp0(tester, withConflict: false);
    await tester.pumpWidget(
      conflictApp(
        locale: 'uk',
        home: Scaffold(
          body: ZenConflictBanner(store: fixture.phone, sources: const [], issues: [issues()]),
        ),
      ),
    );
    expect(find.text('1 запис потребує вашого вибору.'), findsOneWidget);
  });

  testWidgets('the issue rows and screen meet contrast, target size and naming', (tester) async {
    final handle = tester.ensureSemantics();
    await setUp0(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.tap(find.text('Holiday goal is below zero'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('actions that ask for input', () {
    late List<String> chosen;
    late List<String> typed;
    ZenResult<Object?> askOutcome = const ZenResult.ok(null);

    Widget askApp() => conflictApp(
      home: Scaffold(
        body: ZenConflictBanner(
          store: fixture.phone,
          sources: const [],
          issues: [
            ZenIssueSource(
              issues: () => [
                ZenIssue(
                  id: 'ask',
                  title: 'Record has no account',
                  description: 'Its account was deleted elsewhere.',
                  actions: [
                    ZenIssueAction.choose(
                      label: 'Move to account',
                      choices: const [('a', 'Savings'), ('b', 'Wallet'), ('c', 'Cash')],
                      run: (id) async {
                        chosen.add(id);
                        return askOutcome;
                      },
                    ),
                    ZenIssueAction.text(
                      label: 'Bring it back',
                      fieldLabel: 'Name',
                      run: (text) async {
                        typed.add(text);
                        return askOutcome;
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    Future<void> open(WidgetTester tester) async {
      chosen = [];
      typed = [];
      askOutcome = const ZenResult.ok(null);
      await setUp0(tester, withConflict: false);
      await tester.pumpWidget(askApp());
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record has no account'));
      await tester.pumpAndSettle();
    }

    testWidgets('choosing the second candidate runs once with its id', (tester) async {
      await open(tester);
      await tester.tap(find.text('Move to account'));
      await tester.pumpAndSettle();
      expect(find.text('Savings'), findsOneWidget);
      expect(find.text('Wallet'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      await tester.tap(find.text('Wallet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(chosen, ['b']);
    });

    testWidgets('cancelling the text prompt runs nothing and keeps the issue', (tester) async {
      await open(tester);
      await tester.tap(find.text('Bring it back'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Old account');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(typed, isEmpty);
      expect(chosen, isEmpty);
      expect(find.text('Record has no account'), findsOneWidget);
      expect(find.text('Bring it back'), findsOneWidget);
    });

    testWidgets('entering a text runs with it', (tester) async {
      await open(tester);
      await tester.tap(find.text('Bring it back'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Old account');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(typed, ['Old account']);
    });

    testWidgets('a failing run is shown and the issue stays', (tester) async {
      await open(tester);
      askOutcome = const ZenResult.err(ZenValidationError('Name taken.'));
      await tester.tap(find.text('Bring it back'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Old account');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(typed, ['Old account']);
      expect(find.text('Couldn\'t do that: Name taken.'), findsOneWidget);
      expect(find.text('Bring it back'), findsOneWidget);
    });

    bool continueEnabled(WidgetTester tester) =>
        tester.widget<ZenButton>(find.widgetWithText(ZenButton, 'Continue')).onPressed != null;

    testWidgets('cancelling the choice prompt runs nothing and keeps the issue', (tester) async {
      await open(tester);
      await tester.tap(find.text('Move to account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wallet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(chosen, isEmpty);
      expect(find.text('Move to account'), findsOneWidget);
    });

    testWidgets('Continue stays disabled with no choice', (tester) async {
      await open(tester);
      await tester.tap(find.text('Move to account'));
      await tester.pumpAndSettle();
      expect(continueEnabled(tester), isFalse);
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('Continue stays disabled for whitespace-only text', (tester) async {
      await open(tester);
      await tester.tap(find.text('Bring it back'));
      await tester.pumpAndSettle();
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode.hasFocus,
        isTrue,
        reason: 'the text field is focused as the prompt opens',
      );
      expect(continueEnabled(tester), isFalse);
      await tester.enterText(find.byType(EditableText), '   ');
      await tester.pump();
      expect(continueEnabled(tester), isFalse);
      expect(typed, isEmpty);
    });

    testWidgets('Enter submits the trimmed text', (tester) async {
      await open(tester);
      await tester.tap(find.text('Bring it back'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), '  Old account ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(typed, ['Old account']);
    });

    testWidgets('a second tap before the prompt shows opens no second prompt', (tester) async {
      await open(tester);
      await tester.tap(find.text('Move to account'));
      await tester.tap(find.text('Move to account'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      await tester.tap(find.text('Wallet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(chosen, ['b']);
    });
  });
}
