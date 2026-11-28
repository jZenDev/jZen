import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_store/src/state/zen_conflict_sweep.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import 'support/conflict_fixture.dart';
import 'support/devices_fixture.dart';

/// A conflict with two versions under one device's name: both are shown, told apart, and can be
/// chosen, and a choice for many records leaves such a record to the person.
void main() {
  late DevicesFixture fixture;

  tearDown(() async => fixture.dispose());

  /// On each of [twice] the Mac and the phone write "agreed", the Mac merges the two into one
  /// version under the phone's name, and the phone writes "changed" before receiving that merge.
  /// With [others], they also disagree plainly on r2 and r3.
  Future<void> setUp(
    WidgetTester tester, {
    List<String> twice = const ['r1'],
    bool others = false,
  }) async {
    // Tall enough that every card and name is built.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    fixture = (await tester.runAsync(() async {
      final f = await DevicesFixture.create(['Work Mac', 'My iPhone'], offline: true);
      await f.seed(['r1', 'r2', 'r3']);
      for (final id in twice) {
        await f.edit('Work Mac', id, 'agreed');
        await f.edit('My iPhone', id, 'agreed');
      }
      await f.sync('My iPhone');
      await f.sync('Work Mac');
      for (final id in twice) {
        await f.edit('My iPhone', id, 'changed');
      }
      await f.syncAll();
      if (others) {
        for (final id in ['r2', 'r3']) {
          await f.edit('My iPhone', id, 'phone-$id');
          await f.edit('Work Mac', id, 'mac-$id');
        }
        await f.syncAll();
      }
      return f;
    }))!;
  }

  Widget list() => conflictApp(
    home: ZenConflictsScreen(store: fixture['Work Mac'], sources: [fixture.source('Work Mac')]),
  );

  Future<void> tapAndWrite(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('the list names the device once and says it has two versions', (tester) async {
    await setUp(tester);

    await tester.pumpWidget(list());

    expect(find.text('My iPhone (2 versions)'), findsOneWidget);
  });

  testWidgets('each version is a card of its own, told apart by its heading', (tester) async {
    final handle = tester.ensureSemantics();
    await setUp(tester);
    await tester.pumpWidget(list());
    await tester.tap(find.text('Record r1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('My iPhone, version 1 of 2, '), findsOneWidget);
    expect(find.textContaining('My iPhone, version 2 of 2, '), findsOneWidget);
    expect(find.text('agreed'), findsOneWidget);
    expect(find.text('changed'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('the headings speak Ukrainian when the app does', (tester) async {
    await setUp(tester);
    await tester.pumpWidget(
      conflictApp(
        locale: 'uk',
        home: ZenConflictsScreen(store: fixture['Work Mac'], sources: [fixture.source('Work Mac')]),
      ),
    );

    expect(find.text('My iPhone (2 версії)'), findsOneWidget);
    await tester.tap(find.text('Record r1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('My iPhone, версія 2 з 2, '), findsOneWidget);
  });

  for (final wanted in ['agreed', 'changed']) {
    testWidgets('"$wanted" can be chosen, and every device ends with it', (tester) async {
      await setUp(tester);
      await tester.pumpWidget(list());
      await tester.tap(find.text('Record r1'));
      await tester.pumpAndSettle();

      await tapAndWrite(
        tester,
        find.descendant(
          of: find.ancestor(of: find.text(wanted), matching: find.byType(ZenConflictSideCard)),
          matching: find.text('Keep this version'),
        ),
      );
      await tester.runAsync(fixture.syncAll);

      for (final device in ['Work Mac', 'My iPhone']) {
        expect(fixture[device].conflictCount, 0);
        expect(fixture.items(device).get('r1').dataOrNull?.version, wanted);
      }
    });
  }

  testWidgets('a view of two versions from one device is still current', (tester) async {
    await setUp(tester);

    final view = fixture.source('Work Mac').views(notSet: '-').dataOrNull!.single;

    expect(view.isCurrent(), isTrue);
    await tester.runAsync(() => fixture.items('Work Mac').resolve('r1', null));
    expect(view.isCurrent(), isFalse);
  });

  testWidgets('records with both versions from one device offer no choice for many', (
    tester,
  ) async {
    await setUp(tester, twice: ['r1', 'r2']);
    final views = fixture.source('Work Mac').views(notSet: '-').dataOrNull!;
    for (final view in views) {
      expect(view.sides.map((side) => side.device), [
        fixture['My iPhone'].deviceId,
        fixture['My iPhone'].deviceId,
      ]);
    }

    expect(ZenConflictSweep.of(views, thisDevice: fixture['Work Mac'].deviceId), isEmpty);

    await tester.pumpWidget(list());
    expect(find.textContaining('Settle all'), findsNothing);
    expect(find.text('My iPhone (2 versions)'), findsNWidgets(2));
  });

  testWidgets('a choice for many records names such a record and leaves it', (tester) async {
    await setUp(tester, others: true);
    final views = fixture.source('Work Mac').views(notSet: '-').dataOrNull!;
    final sweep = ZenConflictSweep.of(views, thisDevice: fixture['Work Mac'].deviceId).single;

    expect(sweep.included.map((c) => c.id), ['r2', 'r3']);
    expect(sweep.left.map((c) => c.id), ['r1']);

    await tester.pumpWidget(list());
    await tester.tap(find.text('Settle all 2 changed on Work Mac and My iPhone'));
    await tester.pumpAndSettle();
    expect(find.text('Left for you (1)'), findsOneWidget);
    expect(find.textContaining('more than one version from one device'), findsOneWidget);

    await tapAndWrite(tester, find.text("Keep My iPhone's version for all 2"));
    await tester.runAsync(fixture.syncAll);

    for (final id in ['r2', 'r3']) {
      expect(fixture.items('Work Mac').get(id).dataOrNull?.version, 'phone-$id');
    }
    expect(fixture['Work Mac'].conflictCount, 1);
    expect(fixture.items('Work Mac').conflictFor('r1').dataOrNull?.sides, hasLength(2));
  });
}
