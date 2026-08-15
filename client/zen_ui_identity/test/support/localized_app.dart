import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

/// Wraps [home] in the `MaterialApp` a consuming application would build: the identity
/// delegate registered, and an explicit [locale].
///
/// This replaces the per-test fake localization service the string-key era needed. The
/// screens now resolve their wording from the ambient `Localizations`, so a test asserts the
/// package's *real* strings, and pumping the same tree with a different [locale] is exactly
/// what a user switching language does.
///
/// [supported] is the **application's** locale set (ADR-044), defaulting to what jZen ships. A
/// test passes a wider one to stand in for an app that supports a language this package has no
/// strings for. It must list every locale the test pumps: `MaterialApp` resolves `locale`
/// against `supportedLocales`, so a tag missing from it never reaches `Localizations` at all.
Widget localizedApp({
  required Widget home,
  String locale = ZenLocales.en,
  ThemeData? theme,
  List<String> supported = ZenLocales.shipped,
  List<LocalizationsDelegate<dynamic>> extraDelegates = const [],
}) => MaterialApp(
  locale: Locale(locale),
  // identityLocaleDelegate, not the generated IdentityLocalizations.delegate: the degrading one
  // is what an application composes, so the tests exercise the same path an app does.
  localizationsDelegates: [
    // An application's own overrides come first: Localizations takes the first delegate per type
    // that supports the locale, so this is the seam ADR-044 documents.
    ...extraDelegates,
    identityLocaleDelegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: [for (final tag in supported) Locale(tag)],
  theme: theme ?? ThemeData(extensions: [IdentityThemeExtension.fallback()]),
  home: home,
);

/// The identity strings for [locale], for tests that need an expected value without pumping
/// a widget (or that assert one language against the other).
Future<IdentityLocalizations> identityMessages(String locale) =>
    IdentityLocalizations.delegate.load(Locale(locale));
