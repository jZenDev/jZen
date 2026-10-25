import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zen_core/zen_core.dart';

import 'generated/store_localizations.dart';

/// The delegate an application composes to get this package's strings — the degrading one.
///
/// Like `identityLocaleDelegate`, it never refuses a locale: it loads the best match it has, so an
/// app in a language jZen ships no strings for gets English conflict screens rather than a crash
/// on its first conflict (ADR-044).
class StoreLocaleDelegate extends LocalizationsDelegate<StoreLocalizations> {
  const StoreLocaleDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<StoreLocalizations> load(Locale locale) => SynchronousFuture<StoreLocalizations>(
    lookupStoreLocalizations(Locale(ZenLocales.resolve(locale.languageCode))),
  );

  @override
  bool shouldReload(StoreLocaleDelegate old) => false;
}

/// The delegate to put in `MaterialApp.localizationsDelegates` for this package's wording.
const LocalizationsDelegate<StoreLocalizations> storeLocaleDelegate = StoreLocaleDelegate();
