import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';

/// The example's chosen locale, feeding `MaterialApp.locale`.
///
/// Holding a [Locale] rather than a language-code string is the typed half of the same move
/// that replaced string-key lookups with generated accessors (ADR-009): what it may hold is
/// `ZenLocales.supported`, and `Localizations` re-renders every dependent when it changes, so
/// no screen has to observe the language itself.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale(ZenLocales.fallback);

  void setLocale(Locale locale) => state = locale;
}

/// Provider for the current locale.
final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);
