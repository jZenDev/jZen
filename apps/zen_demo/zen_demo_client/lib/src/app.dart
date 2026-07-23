import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

import 'l10n/generated/demo_localizations.dart';
import 'providers.dart';
import 'screens/auth_flow.dart';
import 'screens/home_shell.dart';

/// The root of zen_demo. Routes on the identity session: anonymous -> the auth flow,
/// authenticated -> the home shell. This is the state-based routing DartZen's ZenDemoApp used,
/// rebuilt on Riverpod so the reused zen_ui_identity/navigation packages drive the same session
/// the SupabaseIdentityRepository holds.
///
/// There is no localization boot phase any more (ADR-009): the strings are generated Dart
/// compiled into the binary, so there is nothing to fetch before the first frame - only a
/// locale to choose, which `MaterialApp` propagates through `Localizations`.
class DemoApp extends ConsumerWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'jZen Demo',
      locale: ref.watch(localeProvider),
      // Per-package generation (ADR-009): the app registers its own delegate plus one per
      // localized framework package it renders, and Flutter's own Material/Cupertino/Widgets
      // sets come along in DemoLocalizations.localizationsDelegates.
      localizationsDelegates: const [
        ...DemoLocalizations.localizationsDelegates,
        IdentityLocalizations.delegate,
        NavigationLocalizations.delegate,
      ],
      supportedLocales: DemoLocalizations.supportedLocales,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const _Root(),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      extensions: [
        IdentityThemeExtension(
          successColor: Colors.green,
          errorColor: scheme.error,
          warningColor: Colors.orange,
          brandColor: scheme.primary,
          surfaceColor: scheme.surface,
          titleStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          subtitleStyle: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(identitySessionStoreProvider);

    return session.when(
      loading: () => const _Splash(),
      error: (_, _) => const AuthFlow(),
      data: (identity) =>
          identity == null ? const AuthFlow() : const HomeShell(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
