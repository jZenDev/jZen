import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_folder/zen_store_folder.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_ui_store/zen_ui_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'package:zen_demo_local_client/src/core/device_session.dart';
import 'package:zen_demo_local_client/src/demo_local_app.dart';
import 'package:zen_demo_local_client/src/l10n/generated/local_localizations.dart';
import 'package:zen_demo_local_client/src/widgets/device_section.dart';
import 'package:zen_demo_local_client/src/widgets/shared_folder_controls.dart';

import 'support/bare_session.dart';

/// The settings flows through the app's own wiring: the PIN, the sync folder and pairing (which
/// the build's transport choice would hide on a macOS host, so the controls are mounted as
/// Settings mounts them on Android, Windows and Linux), and what happens when each fails.
void main() {
  Widget host(DeviceSession session, Widget Function() child) => MaterialApp(
    localizationsDelegates: const [
      ...LocalDemoLocalizations.localizationsDelegates,
      ...GlobalMaterialLocalizations.delegates,
      storeLocaleDelegate,
      zenWidgetsLocaleDelegate,
    ],
    supportedLocales: const [Locale('en'), Locale('uk')],
    home: Scaffold(
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) => ListView(children: [child()]),
      ),
    ),
  );

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text, skipOffstage: false).first;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('PIN', () {
    testWidgets('turned on through the settings switch and off again', (tester) async {
      final session = await openBareSession(tester);
      final lock = (await ZenPinLock.load(
        storage: ZenMemoryLockStorage(),
        iterations: 1,
      )).dataOrNull!;
      await tester.pumpWidget(DemoLocalApp(session: session, lock: lock));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Settings').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(lock.isEnabled, isFalse);
      // ignore: avoid_print
      print(
        'DBG ${tester.widgetList<Text>(find.byType(Text, skipOffstage: false)).map((t) => t.data).toList()}',
      );

      await tap(tester, 'Lock with PIN');
      expect(find.text('Set a PIN'), findsWidgets);
      await tester.enterText(find.byType(EditableText).at(0), '2468');
      await tester.enterText(find.byType(EditableText).at(1), '2468');
      await tap(tester, 'Save');
      await tester.pump(const Duration(seconds: 1));
      expect(lock.isEnabled, isTrue);

      await tap(tester, 'Lock with PIN');
      expect(find.text('Turn Off PIN'), findsWidgets);
      await tester.enterText(find.byType(EditableText).first, '2468');
      await tap(tester, 'Turn Off');
      await tester.pump(const Duration(seconds: 1));
      expect(lock.isEnabled, isFalse);
    });
  });

  group('sync folder and pairing', () {
    testWidgets('choose a folder, make this the first device, then show the code', (tester) async {
      final folder = Directory.systemTemp;
      final session = await openBareSession(
        tester,
        pickFolder: () async => ZenFolderChoice(
          reference: folder.path,
          label: 'Shared',
          access: ZenDirectoryAccess(folder),
        ),
      );
      await tester.pumpWidget(host(session, () => SharedFolderControls(session: session)));
      await tester.pumpAndSettle();
      expect(find.textContaining('No folder chosen'), findsOneWidget);
      expect(find.text('Add a device'), findsNothing);

      await tap(tester, 'Choose folder');
      expect(find.textContaining('Shared'), findsOneWidget);
      expect(find.text('Change folder'), findsOneWidget);

      await tap(tester, 'Start syncing from this device');
      expect(session.hasSyncKey, isTrue);
      expect(find.text('Add a device'), findsOneWidget);

      await tap(tester, 'Add a device');
      expect(find.text('Add a Device'), findsWidgets);
      expect(find.text('Show Code'), findsOneWidget);
    });

    testWidgets('joining opens the join screen, and a wrong code is refused with a reason', (
      tester,
    ) async {
      final session = await openBareSession(tester);
      await tester.pumpWidget(host(session, () => SharedFolderControls(session: session)));

      await tester.pumpAndSettle();
      await tap(tester, 'Join another device');
      expect(find.text('Join'), findsWidgets);

      await tester.enterText(find.byType(EditableText).first, 'ABC');
      await tap(tester, 'Join');
      expect(find.textContaining('not the whole code'), findsOneWidget);
      expect(session.hasSyncKey, isFalse);
    });

    testWidgets('a pairing code from another device is accepted and the key kept', (tester) async {
      final session = await openBareSession(tester);
      final key = List<int>.generate(32, (i) => i + 1);
      await tester.pumpWidget(host(session, () => SharedFolderControls(session: session)));

      await tester.pumpAndSettle();
      await tap(tester, 'Join another device');
      final offer = ZenPairing.offer(key, now: DateTime.now());
      await tester.enterText(find.byType(EditableText).first, offer.text);
      await tap(tester, 'Join');

      expect(session.syncKey, key);
      expect(find.text('Add a device'), findsOneWidget);
    });
  });

  group('failures are shown, not swallowed', () {
    testWidgets('a keystore that refuses the sync key says so', (tester) async {
      final session = await openBareSession(tester, secrets: RefusingStorage());
      await tester.pumpWidget(host(session, () => SharedFolderControls(session: session)));

      await tester.pumpAndSettle();
      await tap(tester, 'Start syncing from this device');

      expect(find.textContaining('Could not set up syncing'), findsOneWidget);
      expect(session.hasSyncKey, isFalse);
    });

    testWidgets('a folder dialog that fails says so; cancelling says nothing', (tester) async {
      var fail = true;
      final session = await openBareSession(
        tester,
        pickFolder: () async => fail ? throw StateError('no dialog') : null,
      );
      await tester.pumpWidget(host(session, () => SharedFolderControls(session: session)));

      await tester.pumpAndSettle();
      await tap(tester, 'Choose folder');
      expect(find.textContaining('Could not use that folder'), findsOneWidget);

      fail = false;
      await tester.pump(const Duration(seconds: 10));
      await tap(tester, 'Choose folder');
      expect(find.textContaining('Could not use that folder'), findsNothing);
    });

    testWidgets('a keystore that refuses the folder says so', (tester) async {
      final folder = Directory.systemTemp;
      final session = await openBareSession(
        tester,
        secrets: RefusingStorage(),
        pickFolder: () async =>
            ZenFolderChoice(reference: folder.path, label: 'x', access: ZenDirectoryAccess(folder)),
      );
      await tester.pumpWidget(host(session, () => SharedFolderControls(session: session)));

      await tester.pumpAndSettle();
      await tap(tester, 'Choose folder');

      expect(find.textContaining('Could not use that folder'), findsOneWidget);
      expect(session.folder, isNull);
    });

    testWidgets('an erase that fails is reported by the session as a failure, not thrown', (
      tester,
    ) async {
      final session = await openBareSession(tester);
      await tester.pumpWidget(host(session, () => DeviceSection(session: session)));
      await tester.pumpAndSettle();
      expect(find.text("Erase this device's copy"), findsOneWidget);

      // The store's directory is gone, so erasing cannot succeed, and reopening cannot either.
      final directory = session.directory;
      await tester.runAsync(() => directory.delete(recursive: true));
      await tester.runAsync(() => File(directory.path).writeAsString('not a directory'));
      final result = (await tester.runAsync(session.eraseThisDevice))!;

      expect(result, isA<ZenFailure<void>>());
      await tester.runAsync(() => File(directory.path).delete());
    });
  });
}
