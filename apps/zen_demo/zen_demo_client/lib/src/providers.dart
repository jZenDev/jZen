import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';

import 'demo_repository.dart';

/// The demo endpoint client. Overridden in [ProviderScope] with an instance sharing the session
/// http.Client (see main.dart), so it must be provided by the app.
final demoRepositoryProvider = Provider<DemoRepository>((ref) {
  throw UnimplementedError('demoRepositoryProvider must be overridden');
});

/// The languages this application supports.
///
/// The **application's** decision, not the framework's (ADR-044): `ZenLocales.shipped` is what
/// jZen has ARB files for, and an app is free to support more. zen_demo deliberately supports
/// exactly the shipped set - it is the framework's showcase, so any locale it added would be a
/// locale the framework could not answer in. A product app declares its own list here, and the
/// framework delegates degrade to English for anything jZen ships no strings for.
const List<String> demoSupportedLocales = ZenLocales.shipped;

/// The current UI locale, one of [demoSupportedLocales].
///
/// It has two jobs, and keeping them on one provider is what makes the language switch honest:
///
/// 1. it is `MaterialApp.locale`, so `Localizations` re-renders every screen reading the
///    generated `DemoLocalizations` / `IdentityLocalizations` / `NavigationLocalizations`;
/// 2. its language code is what `ZenClient` emits as `Accept-Language` on every request
///    (ADR-007) - main.dart hands `ZenClient` a callback that reads *this* notifier, so a
///    mid-session switch reaches the next request, including `POST /auth/register`, where the
///    server seeds `users.language` and every later localized email follows from it.
///
/// A [Locale] rather than a language-code string: [demoSupportedLocales] is a set of tags, and
/// a `Locale` is what Flutter's localization stack consumes.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale(ZenLocales.fallback);

  void setLocale(Locale locale) => state = locale;
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
