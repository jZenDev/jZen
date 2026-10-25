import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zen_core/zen_core.dart';

import 'generated/lock_localizations.dart';

/// The delegate an application composes to get this package's strings — the degrading one.
///
/// Like `identityLocaleDelegate`, it never refuses a locale: it loads the best match it has
/// (exact primary subtag, else [ZenLocales.fallback]), so an app in a language jZen ships no lock
/// strings for gets English lock chrome rather than a crash on the first locked launch (ADR-044).
class LockLocaleDelegate extends LocalizationsDelegate<LockLocalizations> {
  const LockLocaleDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<LockLocalizations> load(Locale locale) => SynchronousFuture<LockLocalizations>(
    lookupLockLocalizations(Locale(ZenLocales.resolve(locale.languageCode))),
  );

  @override
  bool shouldReload(LockLocaleDelegate old) => false;
}

/// The delegate to put in `MaterialApp.localizationsDelegates` for this package's wording.
const LocalizationsDelegate<LockLocalizations> lockLocaleDelegate = LockLocaleDelegate();
