import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zen_core/zen_core.dart';

import 'generated/identity_localizations.dart';

/// The delegate an application composes to get this package's strings — the degrading one.
///
/// `IdentityLocalizations.delegate` (generated) answers `isSupported` with a closed list of the
/// locales this package has ARB files for, which is the right answer to the wrong question. A
/// delegate that refuses is not skipped: nothing loads `IdentityLocalizations` for that locale,
/// `IdentityLocalizations.of(context)` is null, and the first framework screen to read a string
/// throws. So an application supporting a language jZen ships no strings for could not use a
/// framework screen at all (ADR-044).
///
/// This delegate never refuses. It loads the best match it *has* — exact primary subtag, else
/// [ZenLocales.fallback] — so an unshipped locale degrades to English chrome around an app that
/// renders its own content in that language, instead of crashing.
///
/// **To translate these strings yourself**, subclass the exported `abstract
/// IdentityLocalizations`, wrap it in your own delegate, and compose that delegate *before* this
/// one: Flutter's `Localizations` takes the first delegate per type that supports the locale.
/// Delete the override if jZen later ships the locale.
class IdentityLocaleDelegate extends LocalizationsDelegate<IdentityLocalizations> {
  const IdentityLocaleDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<IdentityLocalizations> load(Locale locale) => SynchronousFuture<IdentityLocalizations>(
    lookupIdentityLocalizations(Locale(ZenLocales.resolve(locale.languageCode))),
  );

  @override
  bool shouldReload(IdentityLocaleDelegate old) => false;
}

/// The delegate to put in `MaterialApp.localizationsDelegates` for this package's wording.
const LocalizationsDelegate<IdentityLocalizations> identityLocaleDelegate =
    IdentityLocaleDelegate();
