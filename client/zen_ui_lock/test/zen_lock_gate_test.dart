import 'package:flutter/foundation.dart';
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
    final lock = await memoryLock(pin: '2468', owner: PassingOwner());
    await tester.pumpWidget(lockedApp(lock: lock));
    await tester.pumpAndSettle();

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

  group('on a device that cannot check its owner (Linux)', () {
    testWidgets('with no eraser there is no "Forgot PIN?" at all', (tester) async {
      final lock = await memoryLock(pin: '2468', owner: NoOwnerCheck());
      await tester.pumpWidget(lockedApp(lock: lock));
      await tester.pumpAndSettle();

      expect(find.text('Forgot PIN?'), findsNothing);
      expect((await lock.recoveryOption()).dataOrNull, ZenPinRecovery.none);
    });

    testWidgets('"Forgot PIN?" asks first, then erases the copy and removes the PIN', (
      tester,
    ) async {
      var erased = 0;
      final lock = await memoryLock(
        pin: '2468',
        owner: NoOwnerCheck(),
        erase: () async {
          erased++;
          return const ZenResult.ok(null);
        },
      );
      await tester.pumpWidget(lockedApp(lock: lock));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();
      expect(erased, 0, reason: 'nothing is erased before the person confirms');
      expect(find.text("Erase this device's copy?"), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Unlock'), findsOneWidget);
      expect(lock.isEnabled, isTrue);

      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erase and Reset PIN'));
      await tester.pumpAndSettle();

      expect(erased, 1);
      expect(lock.isEnabled, isFalse);
      expect(find.text('secret balance'), findsOneWidget);
    });

    testWidgets('a failed erase keeps the app locked and says so', (tester) async {
      final lock = await memoryLock(
        pin: '2468',
        owner: NoOwnerCheck(),
        erase: () async => const ZenResult.err(ZenUnknownError('disk')),
      );
      await tester.pumpWidget(lockedApp(lock: lock));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erase and Reset PIN'));
      await tester.pumpAndSettle();

      expect(lock.isEnabled, isTrue);
      expect(lock.isLocked, isTrue);
      expect(
        find.text("Couldn't erase this device's copy. The PIN was not reset."),
        findsOneWidget,
      );
    });
  });

  testWidgets('when the owner check cannot be probed it says so, offers a retry, never erase', (
    tester,
  ) async {
    final owner = FailingProbeOwner();
    final lock = await memoryLock(
      pin: '2468',
      owner: owner,
      erase: () async => const ZenResult.ok(null),
    );
    await tester.pumpWidget(lockedApp(lock: lock));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't check whether"), findsOneWidget);
    expect(find.text('Forgot PIN?'), findsNothing);
    expect(find.text('Erase and Reset PIN'), findsNothing);

    owner.fails = false;
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot PIN?'), findsOneWidget);
    expect(find.textContaining("Couldn't check whether"), findsNothing);
  });

  // The privacy cover and the lifecycle lock rest on `AppLifecycleListener`; what differs by
  // platform is which states the engine sends. A desktop window that loses focus is only
  // `inactive`; a phone's app switcher is `inactive` then `hidden`.
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS]) {
    testWidgets('on ${platform.name}, a window left unfocused long enough locks the app', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final lock = await memoryLock(pin: '2468');
      await tester.pumpWidget(lockedApp(lock: lock, relockAfter: Duration.zero));
      await enterPin(tester, '2468');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('secret balance'), findsOneWidget);
      expect(find.byType(ColoredBox), findsWidgets, reason: 'the cover is drawn');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(lock.isLocked, isTrue);
    });
  }

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS]) {
    testWidgets('on ${platform.name}, a short unfocus does not lock the app', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final lock = await memoryLock(pin: '2468');
      await tester.pumpWidget(lockedApp(lock: lock));
      await enterPin(tester, '2468');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(lock.isLocked, isFalse);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('on ${platform.name}, a brief `inactive` (shade, dialog) does not lock', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final lock = await memoryLock(pin: '2468');
      await tester.pumpWidget(lockedApp(lock: lock, relockAfter: Duration.zero));
      await enterPin(tester, '2468');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(lock.isLocked, isFalse);
    });
  }
}
