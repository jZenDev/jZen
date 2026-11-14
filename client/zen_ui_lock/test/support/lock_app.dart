import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

/// The `MaterialApp` a Local application builds: the lock's delegate composed, and the gate in
/// `builder`, above every route.
Widget lockedApp({
  required ZenPinLock lock,
  Widget home = const Scaffold(body: Text('secret balance')),
  String locale = ZenLocales.en,
  ThemeData? theme,
  Duration relockAfter = const Duration(minutes: 1),
}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: const [
    lockLocaleDelegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: [for (final tag in ZenLocales.shipped) Locale(tag)],
  theme: theme,
  builder: (context, child) => ZenLockGate(lock: lock, relockAfter: relockAfter, child: child!),
  home: home,
);

/// A lock in memory with a cheap hash, so a widget test can unlock it without real time passing.
///
/// The owner check defaults to a device that has one; a test of a device that does not (Linux)
/// passes [NoOwnerCheck] and, optionally, [erase].
Future<ZenPinLock> memoryLock({
  String? pin,
  ZenOwnerCheck? owner,
  ZenDeviceErase? erase,
  int Function()? now,
}) async {
  final lock = (await ZenPinLock.load(
    storage: ZenMemoryLockStorage(),
    owner: owner ?? PassingOwner(),
    eraseDeviceCopy: erase,
    now: now,
    iterations: 10,
  )).dataOrNull!;
  if (pin != null) {
    await lock.enable(pin);
    lock.lock();
  }
  return lock;
}

/// A device whose owner check always passes.
final class PassingOwner implements ZenOwnerCheck {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ZenResult<void>> confirm(String reason) async => const ZenResult.ok(null);
}

/// A device that cannot check its owner: Linux, where `local_auth` has no implementation, or a
/// device with no passcode.
final class NoOwnerCheck implements ZenOwnerCheck {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<ZenResult<void>> confirm(String reason) async =>
      const ZenResult.err(ZenUnauthorizedError('no owner check on this device'));
}
