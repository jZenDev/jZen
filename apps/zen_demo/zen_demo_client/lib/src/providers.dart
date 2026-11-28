import 'dart:ui' show PlatformDispatcher;

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

/// The language list the device is set to, most preferred first, as language tags.
///
/// A provider so a test can say what the device speaks; the default is the platform's own list.
final deviceLanguagesProvider = Provider<List<String>>(
  (ref) => [for (final l in PlatformDispatcher.instance.locales) l.toLanguageTag()],
);

/// How the chosen language is remembered across launches.
///
/// The default keeps it in memory only, which is what a test wants; main.dart overrides it with
/// the persisted one, so a language picked in the picker is still picked after a restart.
final localePreferenceProvider = Provider<ZenLocalePreference>(
  (ref) => ZenLocalePreference(supported: demoSupportedLocales, store: ZenMemoryLocaleStore()),
);

/// The current UI locale, one of [demoSupportedLocales].
///
/// It has three jobs, and keeping them on one provider is what makes the language switch honest:
///
/// 1. it is `MaterialApp.locale`, so `Localizations` re-renders every screen reading the
///    generated `DemoLocalizations` / `IdentityLocalizations` / `NavigationLocalizations`;
/// 2. its language code is what `ZenClient` emits as `Accept-Language` on every request
///    (ADR-007) - main.dart hands `ZenClient` a callback that reads *this* notifier, so a
///    mid-session switch reaches the next request, including `POST /auth/register`, where the
///    server seeds `users.language` and every later localized email follows from it;
/// 3. it is remembered on the device. It starts in the person's earlier choice, else the device's
///    language if supported, else the fallback (`ZenLocalePreference.initial`) - with no server
///    involved, because the sign-in screen is shown before any session exists.
///
/// This is the pattern an application copies: an in-memory notifier that returns the fallback
/// from `build()` forgets the choice on every launch. The persistence and the supported-list
/// check are the framework's (`ZenLocalePreference`, `zen_core`); only the storage is the app's.
///
/// A [Locale] rather than a language-code string: [demoSupportedLocales] is a set of tags, and
/// a `Locale` is what Flutter's localization stack consumes.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() =>
      Locale(ref.read(localePreferenceProvider).initial(ref.read(deviceLanguagesProvider)));

  /// Switches the language now and remembers it. The screens change first, so the switch is
  /// immediate; a failed write is then thrown to the caller rather than swallowed, because the
  /// choice would not survive a restart and that is worth knowing about.
  ///
  /// This is the device half only. A picker calls `LanguageChoice.choose`, which also tells the
  /// server.
  Future<void> setLocale(Locale locale) async {
    final preference = ref.read(localePreferenceProvider);
    final language = preference.match(locale.languageCode);
    if (language == null) {
      throw ArgumentError.value(locale, 'locale', 'is not a supported language');
    }
    state = Locale(language);
    await preference.choose(language);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
