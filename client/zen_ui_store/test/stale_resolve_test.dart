import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_store/src/state/zen_conflict_sweep.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import 'support/conflict_fixture.dart';
import 'support/devices_fixture.dart';

/// A choice is saved only against the versions the person was shown: whatever arrives after the
/// screen was drawn is never replaced unseen.
void main() {
  late DevicesFixture fixture;

  tearDown(() async => fixture.dispose());

  /// The Mac and the phone disagree on [ids]; the iPad has changed them too, but nobody has
  /// received that yet.
  Future<void> setUp(WidgetTester tester, {List<String> ids = const ['r1']}) async {
    // Tall enough that every card is built.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    fixture = (await tester.runAsync(() async {
      final f = await DevicesFixture.create(['Work Mac', 'My iPhone', 'Old iPad'], offline: true);
      await f.seed(ids);
      for (final id in ids) {
        await f.edit('Work Mac', id, 'mac-$id');
        await f.edit('My iPhone', id, 'phone-$id');
        await f.edit('Old iPad', id, 'ipad-$id');
      }
      await f.sync('Work Mac');
      await f.sync('My iPhone');
      await f.sync('Work Mac');
      return f;
    }))!;
  }

  Future<void> openRecord(WidgetTester tester, {String locale = 'en'}) async {
    await tester.pumpWidget(
      conflictApp(
        locale: locale,
        home: ZenConflictsScreen(store: fixture['Work Mac'], sources: [fixture.source('Work Mac')]),
      ),
    );
    await tester.tap(find.text('Record r1'));
    await tester.pumpAndSettle();
  }

  Future<void> tapAndWrite(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
  }

  Finder keep(String version, {String label = 'Keep this version'}) => find.descendant(
    of: find.ancestor(of: find.text(version), matching: find.byType(ZenConflictSideCard)),
    matching: find.text(label),
  );

  Future<void> iPadArrives() async {
    await fixture.sync('Old iPad');
    await fixture.sync('Work Mac');
  }

  /// What a transport would hand the Mac for the iPad's change to [id].
  ZenIncomingRecord fromIPad(String id) =>
      ZenIncomingRecord('items:$id', fixture['Old iPad'].outgoing('items:$id')!.payload, null);

  testWidgets('a version that arrived while the screen was open is shown, not replaced', (
    tester,
  ) async {
    await setUp(tester);
    await openRecord(tester);
    await tester.runAsync(iPadArrives);

    await tapAndWrite(tester, keep('mac-r1'));

    expect(fixture.items('Work Mac').conflictFor('r1').dataOrNull?.sides, hasLength(3));
    expect(find.textContaining('so nothing was saved'), findsOneWidget);
    expect(find.text('ipad-r1'), findsOneWidget);

    // Having seen all three, the person chooses again.
    await tapAndWrite(tester, keep('ipad-r1'));
    expect(fixture['Work Mac'].conflictCount, 0);
    expect(fixture.items('Work Mac').get('r1').dataOrNull?.version, 'ipad-r1');
  });

  testWidgets('the screen says so in Ukrainian when the app speaks it', (tester) async {
    await setUp(tester);
    await openRecord(tester, locale: 'uk');
    await tester.runAsync(iPadArrives);

    await tapAndWrite(tester, keep('mac-r1', label: 'Залишити цю версію'));

    expect(find.textContaining('тому нічого не збережено'), findsOneWidget);
  });

  testWidgets('a record settled elsewhere in the meantime says so and offers the way back', (
    tester,
  ) async {
    await setUp(tester);
    await openRecord(tester);
    await tester.runAsync(() async {
      final items = fixture.items('My iPhone');
      await fixture.sync('My iPhone');
      await items.resolve('r1', items.conflictFor('r1').dataOrNull!.sides.first.value);
      await fixture.sync('My iPhone');
      await fixture.sync('Work Mac');
    });
    final settled = fixture.items('Work Mac').get('r1').dataOrNull;

    await tapAndWrite(tester, keep('mac-r1'));

    expect(find.textContaining('already settled'), findsOneWidget);
    expect(find.byType(ZenConflictSideCard), findsNothing);
    expect(fixture.items('Work Mac').get('r1').dataOrNull, settled);
    await tester.tap(find.text('Back to the list'));
    await tester.pumpAndSettle();
    expect(find.byType(ZenConflictResolveScreen), findsNothing);
  });

  testWidgets('a version already on its way in when the choice is made is not replaced', (
    tester,
  ) async {
    await setUp(tester);
    final view = fixture.source('Work Mac').views(notSet: '-').dataOrNull!.single;

    final saved = await tester.runAsync(() async {
      // Queued ahead of the choice, and not yet applied when it is made.
      final arriving = fixture['Work Mac'].receive([fromIPad('r1')]);
      final result = await view.sides.first.keep();
      await arriving;
      return result.isSuccess;
    });

    expect(saved, isFalse);
    expect(fixture.items('Work Mac').conflictFor('r1').dataOrNull?.sides, hasLength(3));
  });

  testWidgets('a choice for many records counts such a record as changed and settles the rest', (
    tester,
  ) async {
    await setUp(tester, ids: ['r1', 'r2', 'r3']);
    final sweep = ZenConflictSweep.of(
      fixture.source('Work Mac').views(notSet: '-').dataOrNull!,
      thisDevice: fixture['Work Mac'].deviceId,
    ).single;

    final outcome = await tester.runAsync(() async {
      final arriving = fixture['Work Mac'].receive([fromIPad('r1')]);
      final result = await sweep.keep(fixture['Work Mac'].deviceId);
      await arriving;
      return result;
    });

    expect((outcome!.settled, outcome.changed, outcome.failed), (2, 1, false));
    expect(fixture.items('Work Mac').conflictFor('r1').dataOrNull?.sides, hasLength(3));
    expect(fixture['Work Mac'].conflictCount, 1);
  });
}
