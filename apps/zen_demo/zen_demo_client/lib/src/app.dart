import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

import 'l10n/generated/demo_localizations.dart';
import 'providers.dart';
import 'demo_root.dart';

/// The root of zen_demo. Routes on the identity session: anonymous -> the auth flow,
/// authenticated -> the home shell. Routing is state-based on Riverpod, so the reused
/// zen_ui_identity and zen_ui_navigation packages drive the same session the
/// SupabaseIdentityRepository holds.
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
      //
      // The framework packages contribute their *degrading* delegates (ADR-044), not the
      // generated `.delegate`: those resolve an unshipped locale to English instead of declining
      // it, which is what lets an app support a language jZen has no strings for. zen_demo
      // supports exactly the shipped set, so nothing degrades here - it composes them because
      // this is the reference an application copies.
      localizationsDelegates: const [
        ...DemoLocalizations.localizationsDelegates,
        identityLocaleDelegate,
        navigationLocaleDelegate,
      ],
      supportedLocales: [for (final tag in demoSupportedLocales) Locale(tag)],
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      // INSIDE MaterialApp, unlike AuthDeepLinks which wraps it. The two halves of a warm link sit
      // at different heights on purpose: the receiver must outlive every screen, while the thing
      // that reports the outcome needs the ScaffoldMessenger and Localizations that only exist
      // below here.
      home: const ZenAuthLinkListener(child: DemoRoot()),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: brightness);
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
