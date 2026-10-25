import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'support/lock_app.dart';

void main() {
  Future<void> enterPin(WidgetTester tester, String pin) async {
    await tester.enterText(find.byType(EditableText), pin);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
  }

  testWidgets('with no PIN set the app is shown as it is', (tester) async {
    final lock = await memoryLock();

    await tester.pumpWidget(lockedApp(lock: lock));

    expect(find.text('secret balance'), findsOneWidget);
    expect(find.byType(ZenUnlockScreen), findsNothing);
  });

  testWidgets('a locked app is hidden — not shown, not tappable, not read aloud', (tester) async {
    final handle = tester.ensureSemantics();
    final lock = await memoryLock(pin: '2468');

    await tester.pumpWidget(lockedApp(lock: lock));

    expect(find.byType(ZenUnlockScreen), findsOneWidget);
    expect(find.text('secret balance'), findsNothing);
    expect(find.text('secret balance', skipOffstage: false), findsOneWidget);
    expect(find.bySemanticsLabel('secret balance'), findsNothing);
    handle.dispose();
  });

  testWidgets('the right PIN opens the app; a wrong one says so and keeps it closed', (
    tester,
  ) async {
    final lock = await memoryLock(pin: '2468');
    await tester.pumpWidget(lockedApp(lock: lock));

    await enterPin(tester, '1111');
    expect(find.text('Wrong PIN'), findsOneWidget);
    expect(find.text('secret balance'), findsNothing);

    await enterPin(tester, '2468');
    expect(find.text('secret balance'), findsOneWidget);
  });

  testWidgets('after too many wrong PINs the screen says how long to wait and refuses', (
    tester,
  ) async {
    final lock = await memoryLock(pin: '2468');
    await tester.pumpWidget(lockedApp(lock: lock));

    for (var i = 0; i < ZenPinLock.freeAttempts; i++) {
      await enterPin(tester, '0000');
    }

    expect(find.textContaining('Try again in 30 s'), findsOneWidget);
    expect(tester.widget<EditableText>(find.byType(EditableText)).readOnly, isTrue);
  });

  testWidgets('the app locks again once it has been in the background long enough', (tester) async {
    final lock = await memoryLock(pin: '2468');
    await tester.pumpWidget(lockedApp(lock: lock, relockAfter: Duration.zero));
    await enterPin(tester, '2468');
    expect(lock.isLocked, isFalse);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();

    expect(lock.isLocked, isTrue);
    expect(find.byType(ZenUnlockScreen), findsOneWidget);
  });

  testWidgets('a short trip away does not lock it again', (tester) async {
    final lock = await memoryLock(pin: '2468');
    await tester.pumpWidget(lockedApp(lock: lock));
    await enterPin(tester, '2468');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(lock.isLocked, isFalse);
  });

  testWidgets('"Forgot PIN?" removes the PIN once the device owner is confirmed', (tester) async {
    final lock = await memoryLock(pin: '2468', owner: _PassingOwner());
    await tester.pumpWidget(lockedApp(lock: lock));

    await tester.tap(find.text('Forgot PIN?'));
    await tester.pumpAndSettle();

    expect(lock.isEnabled, isFalse);
    expect(find.text('secret balance'), findsOneWidget);
  });

  testWidgets('the switch turns the lock on through the set-up screen', (tester) async {
    final lock = await memoryLock();
    await tester.pumpWidget(
      lockedApp(
        lock: lock,
        home: Scaffold(body: ZenPinLockSwitch(lock: lock)),
      ),
    );

    await tester.tap(find.text('Lock with PIN'));
    await tester.pumpAndSettle();
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), '1357');
    await tester.enterText(fields.at(1), '1358');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text("The PINs don't match"), findsOneWidget);
    expect(lock.isEnabled, isFalse);

    await tester.enterText(fields.at(1), '1357');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(lock.isEnabled, isTrue);
    expect(find.byType(ZenPinSetupScreen), findsNothing);
  });

  testWidgets('the screens speak Ukrainian when the app does', (tester) async {
    final lock = await memoryLock(pin: '2468');

    await tester.pumpWidget(lockedApp(lock: lock, locale: 'uk'));

    expect(find.text('Введіть PIN-код'), findsOneWidget);
    expect(find.text('Розблокувати'), findsOneWidget);
  });
}

final class _PassingOwner implements ZenOwnerCheck {
  @override
  Future<ZenResult<void>> confirm(String reason) async => const ZenResult.ok(null);
}
