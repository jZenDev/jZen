import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'package:zen_demo_local_client/generated/zen_demo_local/v1/chore.pb.dart';
import 'package:zen_demo_local_client/src/demo_local_app.dart';

import 'two_devices.dart';

/// The whole app on one of two real devices, driven through its screens.
///
/// File I/O never completes under a widget test's fake clock, so every step that reaches the disk
/// runs inside `runAsync` and is followed by a pump.
final class AppHarness {
  final TwoDevices devices;
  final ZenPinLock lock;
  final WidgetTester tester;

  AppHarness._(this.devices, this.lock, this.tester);

  /// Opens the app on the phone, after [seed] made whatever the test needs on the two devices.
  static Future<AppHarness> pump(
    WidgetTester tester, {
    Future<void> Function(TwoDevices devices)? seed,
  }) async {
    final devices = (await tester.runAsync(() => TwoDevices.create(TransportKind.folderCloud)))!;
    if (seed != null) await tester.runAsync(() => seed(devices));
    final lock = (await tester.runAsync(
      () => ZenPinLock.load(storage: ZenMemoryLockStorage(), iterations: 1),
    ))!.dataOrNull!;
    await tester.pumpWidget(DemoLocalApp(session: devices.phone, lock: lock));
    await tester.pumpAndSettle();
    addTearDown(() async => tester.runAsync(devices.dispose));
    return AppHarness._(devices, lock, tester);
  }

  /// Lets the writes and syncs a tap started finish, then shows the result.
  ///
  /// A handler's file I/O runs in the test's fake-async zone: each step completes on the real
  /// event loop but its continuation only runs when the test pumps. So real time and pumps
  /// alternate, enough times for a write's several steps and a page transition.
  ///
  /// Not `pumpAndSettle`: a focused text field's cursor blinks forever, so a screen with one never
  /// settles.
  Future<void> settle() async {
    for (var i = 0; i < 24; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tapText(String text) => tapFinder(find.text(text));

  Future<void> tapFinder(Finder finder) async {
    final target = finder.first;
    // A form is a scrolling list; a button below the fold is out of reach of a tap.
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await settle();
  }

  Future<void> tapLabel(String label) async {
    await tester.tap(find.bySemanticsLabel(label).first);
    await settle();
  }
}

/// A chore made on the laptop and synced, then edited on both devices so they disagree about its
/// title: the conflict a person would meet after working offline on two devices.
Future<void> titleConflict(TwoDevices devices) async {
  final chore = Chore(id: devices.laptop.newId(), title: 'Water plants');
  await devices.laptop.chores.save(chore);
  await devices.sync();
  await devices.laptop.chores.save(chore.deepCopy()..title = 'Water the plants');
  await devices.phone.chores.save(chore.deepCopy()..title = 'Water the ferns');
  await devices.sync();
}

/// Two chores on the phone, for the list.
Future<void> twoChores(TwoDevices devices) async {
  await devices.phone.chores.save(
    Chore(id: devices.phone.newId(), title: 'Dishes', note: 'Before 6'),
  );
  await devices.phone.chores.save(Chore(id: devices.phone.newId(), title: 'Laundry', done: true));
}

/// A chore made and synced, then deleted on the laptop while the phone edited its note: the other
/// conflict, a delete against an edit.
Future<void> deleteAgainstEdit(TwoDevices devices) async {
  final chore = Chore(id: devices.laptop.newId(), title: 'Water plants');
  await devices.laptop.chores.save(chore);
  await devices.sync();
  await devices.laptop.chores.remove(chore.id);
  await devices.phone.chores.save(chore.deepCopy()..note = 'Also the basil');
  await devices.sync();
}

/// One chore on both devices, synced.
Future<void> sharedChore(TwoDevices devices) async {
  await devices.laptop.chores.save(Chore(id: devices.laptop.newId(), title: 'Water plants'));
  await devices.sync();
}
