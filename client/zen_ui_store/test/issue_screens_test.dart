import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

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
}
