import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zen_core/zen_core.dart';

import 'generated/zen_widgets_localizations.dart';

/// The delegate an application composes to get this package's strings — the degrading one.
///
/// `ZenWidgetsLocalizations.delegate` (generated) answers `isSupported` with a closed list of the
/// locales this package has ARB files for. A delegate that refuses is not skipped: nothing loads
/// `ZenWidgetsLocalizations` for that locale and the first widget to read a string throws, so an
/// application supporting a language jZen ships no strings for could not use this package at all
/// (ADR-044).
///
/// This delegate never refuses. It loads the best match it *has* — exact primary subtag, else
/// [ZenLocales.fallback] — so an unshipped locale degrades to English chrome rather than crashing.
///
/// **To translate these strings yourself**, subclass the exported `abstract
/// ZenWidgetsLocalizations`, wrap it in your own delegate, and compose that delegate *before* this
/// one: Flutter's `Localizations` takes the first delegate per type that supports the locale.
class ZenWidgetsLocaleDelegate extends LocalizationsDelegate<ZenWidgetsLocalizations> {
  const ZenWidgetsLocaleDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<ZenWidgetsLocalizations> load(Locale locale) => SynchronousFuture<ZenWidgetsLocalizations>(
    lookupZenWidgetsLocalizations(Locale(ZenLocales.resolve(locale.languageCode))),
  );

  @override
  bool shouldReload(ZenWidgetsLocaleDelegate old) => false;
}

/// The delegate to put in `MaterialApp.localizationsDelegates` for this package's wording.
const LocalizationsDelegate<ZenWidgetsLocalizations> zenWidgetsLocaleDelegate =
    ZenWidgetsLocaleDelegate();
