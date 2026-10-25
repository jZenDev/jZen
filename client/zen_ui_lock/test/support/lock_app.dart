import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

/// The `MaterialApp` a light application builds: the lock's delegate composed, and the gate in
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
Future<ZenPinLock> memoryLock({String? pin, ZenOwnerCheck? owner, int Function()? now}) async {
  final lock = (await ZenPinLock.load(
    storage: ZenMemoryLockStorage(),
    owner: owner,
    now: now,
    iterations: 10,
  )).dataOrNull!;
  if (pin != null) {
    await lock.enable(pin);
    lock.lock();
  }
  return lock;
}
