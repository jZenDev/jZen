import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_store/src/state/zen_conflict_sweep.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import 'support/conflict_fixture.dart';
import 'support/devices_fixture.dart';

void main() {
  late DevicesFixture fixture;

  tearDown(() async => fixture.dispose());

  /// Phone and Mac disagree on r1, r2 and r3; r4 is a delete on the Mac against an edit on the
  /// phone. With [tablet], r5 is changed differently on all three devices.
  Future<void> setUp(WidgetTester tester, {bool tablet = false}) async {
    fixture = (await tester.runAsync(() async {
      final f = await DevicesFixture.create(['My iPhone', 'Work Mac', if (tablet) 'Old iPad']);
      await f.seed(['r1', 'r2', 'r3', 'r4', if (tablet) 'r5']);
      for (final id in ['r1', 'r2', 'r3']) {
        await f.edit('My iPhone', id, 'phone-$id');
        await f.edit('Work Mac', id, 'mac-$id');
      }
      await f.items('Work Mac').delete('r4');
      await f.edit('My iPhone', 'r4', 'phone-r4');
      if (tablet) {
        await f.edit('My iPhone', 'r5', 'phone-r5');
        await f.edit('Work Mac', 'r5', 'mac-r5');
        await f.edit('Old iPad', 'r5', 'ipad-r5');
      }
      await f.syncAll();
      return f;
    }))!;
  }

  Widget list() => conflictApp(
    home: ZenConflictsScreen(store: fixture['My iPhone'], sources: [fixture.source('My iPhone')]),
  );

  Future<void> tapAndWrite(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
  }

  Future<void> openBulk(WidgetTester tester) async {
    await tester.pumpWidget(list());
    await tester.tap(find.text('Settle all 3 changed on My iPhone and Work Mac'));
    await tester.pumpAndSettle();
  }

  testWidgets('the list offers one choice for the records two devices disagree on', (tester) async {
    await setUp(tester);
    await tester.pumpWidget(list());

    expect(find.text('Settle all 3 changed on My iPhone and Work Mac'), findsOneWidget);
    // Each record is still listed on its own.
    expect(find.text('Record r1'), findsOneWidget);
    expect(find.text('Record r4'), findsOneWidget);
  });

  testWidgets('before anything is written, the count and each device are named', (tester) async {
    await setUp(tester);
    await openBulk(tester);

    expect(
      find.textContaining('3 items were changed differently on My iPhone and Work Mac'),
      findsOneWidget,
    );
    expect(find.text("Keep this device's version (My iPhone) for all 3"), findsOneWidget);
    expect(find.text("Keep Work Mac's version for all 3"), findsOneWidget);
    expect(find.text('Settled together (3)'), findsOneWidget);
    // Nothing has been written yet.
    expect(fixture['My iPhone'].conflictCount, 4);
  });

  testWidgets('a delete against an edit is named and left, not swept in', (tester) async {
    await setUp(tester);
    await openBulk(tester);

    expect(find.text('Left for you (1)'), findsOneWidget);
    expect(find.text('Record r4'), findsOneWidget);
  });

  testWidgets("keeping this device's version settles every record in the pair on every device", (
    tester,
  ) async {
    await setUp(tester);
    await openBulk(tester);

    await tapAndWrite(tester, find.text("Keep this device's version (My iPhone) for all 3"));
    await tester.runAsync(fixture.syncAll);

    for (final device in ['My iPhone', 'Work Mac']) {
      for (final id in ['r1', 'r2', 'r3']) {
        expect(fixture.items(device).get(id).dataOrNull?.version, 'phone-$id');
      }
    }
    // The delete against an edit is still waiting for the person, on both devices.
    expect(fixture['My iPhone'].conflictCount, 1);
    expect(fixture['Work Mac'].conflictCount, 1);
    expect(find.byType(ZenConflictBulkScreen), findsNothing);
  });

  testWidgets("keeping the other device's version settles them with that device's values", (
    tester,
  ) async {
    await setUp(tester);
    await openBulk(tester);

    await tapAndWrite(tester, find.text("Keep Work Mac's version for all 3"));
    await tester.runAsync(fixture.syncAll);

    for (final id in ['r1', 'r2', 'r3']) {
      expect(fixture.items('My iPhone').get(id).dataOrNull?.version, 'mac-$id');
    }
    expect(fixture['My iPhone'].conflictCount, 1);
  });

  testWidgets('a record a third device also changed is named and left', (tester) async {
    // Tall enough that every name in the list is built.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await setUp(tester, tablet: true);
    await openBulk(tester);

    expect(find.text('Left for you (2)'), findsOneWidget);
    expect(find.text('Record r5'), findsOneWidget);

    await tapAndWrite(tester, find.text("Keep Work Mac's version for all 3"));
    await tester.runAsync(fixture.syncAll);

    expect(fixture['My iPhone'].conflictCount, 2);
    expect(fixture.items('My iPhone').conflictFor('r5').dataOrNull?.sides, hasLength(3));
  });

  testWidgets('a record that changed after it was shown is skipped, and the rest says so', (
    tester,
  ) async {
    await setUp(tester);
    final views = fixture.source('My iPhone').views(notSet: '-').dataOrNull!;
    // r2 is settled by someone else between the screen being drawn and the choice being made.
    await tester.runAsync(() => fixture.items('My iPhone').resolve('r2', null));

    await tester.pumpWidget(
      conflictApp(
        home: ZenConflictBulkScreen(
          sweep: ZenConflictSweep.of(views, thisDevice: fixture['My iPhone'].deviceId).single,
          onDone: () {},
        ),
      ),
    );
    await tapAndWrite(tester, find.text("Keep this device's version (My iPhone) for all 3"));

    expect(
      find.text(
        'Settled 2 of 3. The rest changed in the meantime or could not be saved, and still wait for your choice.',
      ),
      findsOneWidget,
    );
    expect(find.text('Back to the list'), findsOneWidget);
    expect(find.textContaining('Keep'), findsNothing);
  });

  testWidgets('one conflict between two devices offers no choice for many', (tester) async {
    fixture = (await tester.runAsync(() async {
      final f = await DevicesFixture.create(['My iPhone', 'Work Mac']);
      await f.seed(['r1']);
      await f.edit('My iPhone', 'r1', 'a');
      await f.edit('Work Mac', 'r1', 'b');
      await f.syncAll();
      return f;
    }))!;
    await tester.pumpWidget(list());

    expect(find.textContaining('Settle all'), findsNothing);
  });

  testWidgets('the screen lays out at 200% text in Ukrainian', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await setUp(tester, tablet: true);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: conflictApp(
          locale: 'uk',
          home: ZenConflictsScreen(
            store: fixture['My iPhone'],
            sources: [fixture.source('My iPhone')],
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('одразу').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Оберіть пристрій'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('the screen meets AA contrast and target size (${brightness.name})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await setUp(tester);
      await tester.pumpWidget(
        conflictApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
          ),
          home: ZenConflictsScreen(
            store: fixture['My iPhone'],
            sources: [fixture.source('My iPhone')],
          ),
        ),
      );
      await tester.tap(find.textContaining('Settle all'));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  }
}
