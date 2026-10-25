import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import 'support/conflict_fixture.dart';

void main() {
  late ConflictFixture fixture;

  tearDown(() async => fixture.dispose());

  Future<void> setUpConflict(WidgetTester tester, {bool deleteConflict = false}) async => fixture =
      (await tester.runAsync(() => ConflictFixture.create(deleteConflict: deleteConflict)))!;

  Widget banner() => conflictApp(
    home: Scaffold(
      body: Column(
        children: [
          ZenConflictBanner(store: fixture.phone, sources: [fixture.source(fixture.phone)]),
          const Text('main screen'),
        ],
      ),
    ),
  );

  /// A tap whose handler writes to disk, which needs real time to finish.
  Future<void> tapAndWrite(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('the banner says how many choices wait, and takes no space when none do', (
    tester,
  ) async {
    await setUpConflict(tester);
    await tester.pumpWidget(banner());

    expect(find.text('1 item was changed on two devices and needs your choice.'), findsOneWidget);

    await tester.runAsync(() => fixture.items(fixture.phone).resolve('1', null));
    await tester.pumpAndSettle();
    expect(find.byType(ZenConflictBanner), findsOneWidget);
    expect(find.textContaining('changed on two devices'), findsNothing);
  });

  testWidgets('Review lists each record in conflict by the app\'s own title and the devices', (
    tester,
  ) async {
    await setUpConflict(tester);
    await tester.pumpWidget(banner());

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Changed on Two Devices'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('My iPhone · Work Mac'), findsOneWidget);
  });

  testWidgets('each version shows its device, its value, and keeps it on every device', (
    tester,
  ) async {
    await setUpConflict(tester);
    await tester.pumpWidget(
      conflictApp(
        home: ZenConflictsScreen(store: fixture.phone, sources: [fixture.source(fixture.phone)]),
      ),
    );
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Work Mac, '), findsOneWidget);
    expect(find.textContaining('My iPhone, '), findsOneWidget);
    expect(find.text('Amount'), findsNWidgets(2));
    expect(find.text('12.50'), findsOneWidget);
    expect(find.text('14.00'), findsOneWidget);

    final keepMac = find.descendant(
      of: find.ancestor(of: find.text('12.50'), matching: find.byType(ZenConflictSideCard)),
      matching: find.text('Keep this version'),
    );
    await tapAndWrite(tester, keepMac);

    expect(find.byType(ZenConflictResolveScreen), findsNothing);
    expect(find.text('Everything is in sync.'), findsOneWidget);
    await tester.runAsync(fixture.syncAll);
    expect(fixture.items(fixture.mac).get('1').dataOrNull?.version, '12.50');
    expect(fixture.mac.conflictCount, 0);
  });

  testWidgets('without labels from the app, a field is named by its proto name', (tester) async {
    await setUpConflict(tester);
    await tester.pumpWidget(
      conflictApp(
        home: ZenConflictsScreen(
          store: fixture.phone,
          sources: [fixture.source(fixture.phone, labelled: false)],
        ),
      ),
    );
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    expect(find.text('version'), findsNWidgets(2));
  });

  testWidgets('a delete against an edit shows what deleting would throw away', (tester) async {
    await setUpConflict(tester, deleteConflict: true);
    await tester.pumpWidget(
      conflictApp(
        home: ZenConflictsScreen(store: fixture.phone, sources: [fixture.source(fixture.phone)]),
      ),
    );
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    expect(find.text('Deleted on this device'), findsOneWidget);
    expect(find.text('Keep it deleted'), findsOneWidget);
    expect(find.text('14.00'), findsOneWidget);

    await tapAndWrite(tester, find.text('Keep it deleted'));
    expect(fixture.items(fixture.phone).get('1').isFailure, isTrue);
  });

  testWidgets('the screens speak Ukrainian when the app does', (tester) async {
    await setUpConflict(tester);

    await tester.pumpWidget(
      conflictApp(
        locale: 'uk',
        home: ZenConflictsScreen(store: fixture.phone, sources: [fixture.source(fixture.phone)]),
      ),
    );

    expect(find.text('Змінено на двох пристроях'), findsOneWidget);
  });
}
