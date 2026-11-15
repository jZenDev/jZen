import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_ui_store/zen_ui_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'core/device_session.dart';
import 'demo_local_theme.dart';
import 'l10n/generated/local_localizations.dart';
import 'screens/chores_screen.dart';

/// The app: the chore list behind the PIN lock, in English or Ukrainian.
class DemoLocalApp extends StatelessWidget {
  final DeviceSession session;
  final ZenPinLock lock;

  const DemoLocalApp({super.key, required this.session, required this.lock});

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => LocalDemoLocalizations.of(context).appTitle,
    localizationsDelegates: const [
      ...LocalDemoLocalizations.localizationsDelegates,
      storeLocaleDelegate,
      lockLocaleDelegate,
      zenWidgetsLocaleDelegate,
    ],
    supportedLocales: [for (final tag in ZenLocales.shipped) Locale(tag)],
    theme: demoLocalTheme(Brightness.light),
    darkTheme: demoLocalTheme(Brightness.dark),
    // Above the navigator, so a pushed page is covered too (ZenLockGate's contract).
    builder: (context, child) => ZenLockGate(lock: lock, child: child!),
    home: ChoresScreen(session: session, lock: lock),
  );
}
