import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// The person's own flow through the screens: list, add, mark done, conflict, settings, erase.
void main() {
  testWidgets('the list shows the chores, open ones first', (tester) async {
    await AppHarness.pump(tester, seed: twoChores);

    expect(find.text('Dishes'), findsOneWidget);
    expect(find.text('Laundry'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Dishes')).dy,
      lessThan(tester.getTopLeft(find.text('Laundry')).dy),
    );
  });

  testWidgets('an empty list says nothing is sent to a server', (tester) async {
    await AppHarness.pump(tester);

    expect(find.textContaining('nothing is sent to a server'), findsOneWidget);
  });

  testWidgets('a chore is added through the form and saved on this device', (tester) async {
    final app = await AppHarness.pump(tester);

    await app.tapText('Add a chore');
    await tester.enterText(find.byType(EditableText).first, 'Take out the bins');
    await app.tapText('Save');

    expect(find.text('Take out the bins'), findsOneWidget);
    expect(app.devices.phone.chores.list().single.title, 'Take out the bins');
  });

  testWidgets('a chore without a title is refused with a reason', (tester) async {
    final app = await AppHarness.pump(tester);

    await app.tapText('Add a chore');
    await app.tapText('Save');

    expect(find.text('Give the chore a title.'), findsOneWidget);
    expect(app.devices.phone.chores.list(), isEmpty);
  });

  testWidgets('the trailing button marks a chore done', (tester) async {
    final app = await AppHarness.pump(tester, seed: twoChores);

    await app.tapLabel('Done');

    expect(app.devices.phone.chores.list().where((c) => c.done), hasLength(2));
  });

  testWidgets('a chore is deleted from its form', (tester) async {
    final app = await AppHarness.pump(tester, seed: twoChores);

    await app.tapText('Dishes');
    await app.tapText('Delete');

    expect(find.text('Dishes'), findsNothing);
    expect(app.devices.phone.chores.list().map((c) => c.title), ['Laundry']);
  });

  testWidgets('two devices disagreeing show the banner, and choosing a version settles it', (
    tester,
  ) async {
    final app = await AppHarness.pump(tester, seed: titleConflict);

    expect(find.textContaining('your choice'), findsOneWidget);
    await app.tapText('Review');
    // The list names the chore by one of its versions; either row opens the same choice.
    await app.tapFinder(find.textContaining('Water the'));
    await app.tapText('Keep this version');
    // Plain file I/O of the other device, off the test's fake clock.
    await tester.runAsync(app.devices.sync);
    await app.settle();

    expect(app.devices.phone.store.conflictCount, 0);
    expect(app.devices.laptop.store.conflictCount, 0);
    expect(app.devices.phone.chores.list().single.title, startsWith('Water the'));
    expect(
      app.devices.laptop.chores.list().single.title,
      app.devices.phone.chores.list().single.title,
    );
  });

  testWidgets('settings offers the PIN, the sync line and erasing this device', (tester) async {
    final app = await AppHarness.pump(tester);

    await app.tapLabel('Settings');

    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.text("Erase this device's copy"), findsOneWidget);
  });

  testWidgets('erasing this device asks first, and Cancel leaves everything as it was', (
    tester,
  ) async {
    final app = await AppHarness.pump(tester, seed: twoChores);

    await app.tapLabel('Settings');
    await app.tapText("Erase this device's copy");
    expect(find.text("Erase this device's copy?"), findsOneWidget);
    await app.tapText('Cancel');

    expect(find.text("Erase this device's copy?"), findsNothing);
    expect(app.devices.phone.chores.list(), hasLength(2));
    // What Erase does — empty this device, keep the others, get it all back — is the session's
    // own behaviour and is run against both transports in two_devices_test.dart; a widget test
    // cannot run its many disk operations to completion on a fake clock.
  });

  testWidgets('the app speaks Ukrainian when the device does', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('uk')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await AppHarness.pump(tester);

    expect(find.text('Справи'), findsWidgets);
    expect(find.text('Додати справу'), findsOneWidget);
  });
}
