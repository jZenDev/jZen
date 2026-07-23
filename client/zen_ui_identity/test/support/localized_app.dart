import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

/// Wraps [home] in the `MaterialApp` a consuming application would build: the identity
/// delegate registered, and an explicit [locale].
///
/// This replaces the per-test fake localization service the string-key era needed. The
/// screens now resolve their wording from the ambient `Localizations`, so a test asserts the
/// package's *real* strings, and pumping the same tree with a different [locale] is exactly
/// what a user switching language does.
Widget localizedApp({
  required Widget home,
  String locale = ZenLocales.en,
  ThemeData? theme,
}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: IdentityLocalizations.localizationsDelegates,
  supportedLocales: IdentityLocalizations.supportedLocales,
  theme: theme ?? ThemeData(extensions: [IdentityThemeExtension.fallback()]),
  home: home,
);

/// The identity strings for [locale], for tests that need an expected value without pumping
/// a widget (or that assert one language against the other).
Future<IdentityLocalizations> identityMessages(String locale) =>
    IdentityLocalizations.delegate.load(Locale(locale));
