import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:protobuf/well_known_types/google/protobuf/wrappers.pb.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_store/src/state/zen_conflict_sweep.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import 'support/conflict_fixture.dart';
import 'support/devices_fixture.dart';

/// A choice is refused only for the reason given: a record that has not changed is saved whatever
/// it holds, and a write that fails is reported as a failure, not as someone else's choice.
void main() {
  late DevicesFixture fixture;

  tearDown(() async => fixture.dispose());

  Future<void> tapAndWrite(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
  }

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Finder keep(String value) => find.descendant(
    of: find.ancestor(of: find.text(value), matching: find.byType(ZenConflictSideCard)),
    matching: find.text('Keep this version'),
  );

  /// A double, which can hold a NaN: a value that is not equal to itself.
  ZenCollection<DoubleValue> readings(String device) =>
      fixture[device].collection('readings', DoubleValue.fromBuffer);

  ZenConflictSource<DoubleValue> readingSource() =>
      ZenConflictSource<DoubleValue>(collection: readings('Work Mac'), title: (_) => 'Reading');

  for (final (wanted, check) in [('NaN', isNaN), ('2.0', equals(2.0))]) {
    testWidgets('a record holding a NaN can be settled by keeping $wanted', (tester) async {
      tall(tester);
      fixture = (await tester.runAsync(() async {
        final f = await DevicesFixture.create(['Work Mac', 'My iPhone'], offline: true);
        ZenCollection<DoubleValue> on(String device) =>
            f[device].collection('readings', DoubleValue.fromBuffer);
        await on('Work Mac').put('1', DoubleValue(value: 1));
        await f.syncAll();
        await on('Work Mac').put('1', DoubleValue(value: double.nan));
        await on('My iPhone').put('1', DoubleValue(value: 2));
        await f.syncAll();
        return f;
      }))!;
      await tester.pumpWidget(
        conflictApp(
          home: ZenConflictsScreen(store: fixture['Work Mac'], sources: [readingSource()]),
        ),
      );
      await tester.tap(find.text('Reading'));
      await tester.pumpAndSettle();

      await tapAndWrite(tester, keep(wanted));

      expect(find.textContaining('so nothing was saved'), findsNothing);
      expect(fixture['Work Mac'].conflictCount, 0);
      expect(readings('Work Mac').get('1').dataOrNull?.value, check);
    });
  }

  /// The Mac and the phone disagree on r1 and r2.
  Future<void> setUpPlain(WidgetTester tester) async {
    tall(tester);
    fixture = (await tester.runAsync(() async {
      final f = await DevicesFixture.create(['Work Mac', 'My iPhone'], offline: true);
      await f.seed(['r1', 'r2']);
      for (final id in ['r1', 'r2']) {
        await f.edit('Work Mac', id, 'mac-$id');
        await f.edit('My iPhone', id, 'phone-$id');
      }
      await f.syncAll();
      return f;
    }))!;
  }

  for (final (locale, button, message) in [
    ('en', 'Keep this version', "Couldn't save your choice. Try again."),
    ('uk', 'Залишити цю версію', 'Не вдалося зберегти ваш вибір. Спробуйте ще раз.'),
  ]) {
    testWidgets('a choice that cannot be written says so, not that it was settled ($locale)', (
      tester,
    ) async {
      await setUpPlain(tester);
      await tester.pumpWidget(
        conflictApp(
          locale: locale,
          home: ZenConflictsScreen(
            store: fixture['Work Mac'],
            sources: [fixture.source('Work Mac')],
          ),
        ),
      );
      await tester.tap(find.text('Record r1'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => fixture['Work Mac'].eraseEverywhere());

      await tapAndWrite(tester, find.text(button).first);

      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('already settled'), findsNothing);
      // The versions stay, so the person can try again.
      expect(find.byType(ZenConflictSideCard), findsNWidgets(2));
    });
  }

  testWidgets('a choice for many records ends at a write that cannot be made', (tester) async {
    await setUpPlain(tester);
    final sweep = ZenConflictSweep.of(
      fixture.source('Work Mac').views(notSet: '-').dataOrNull!,
      thisDevice: fixture['Work Mac'].deviceId,
    ).single;

    final outcome = await tester.runAsync(() async {
      await fixture['Work Mac'].eraseEverywhere();
      return sweep.keep(fixture['Work Mac'].deviceId);
    });

    expect((outcome!.settled, outcome.changed, outcome.failed), (0, 0, true));
  });
}
