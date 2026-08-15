/// The locales jZen itself ships strings for, in one place, on the client side.
///
/// This is the Dart mirror of `zen.core.i18n.ZenLocales` (server/zen-core): the same set, the
/// same fallback, the same primary-subtag matching, so a language jZen can render is a language
/// jZen can answer in. The two declarations are deliberately separate files rather than a
/// generated pair - the set is three lines and changes once per locale, whereas a generator
/// would be exactly the "custom magic" the MANIFESTO forbids.
///
/// **[shipped] is an inventory, not a policy** (ADR-044). It says which locales *jZen's own
/// packages* have ARB files for. It is **not** the set of languages an application supports:
/// that is the application's decision, declared as a compile-time `const` list it hands to the
/// delegates it composes (and, on the server, as the runtime property `zen.i18n.supported`). An
/// app may support a locale jZen ships nothing for - each framework delegate degrades to
/// [fallback] for it rather than refusing, so the app's own screens render in that language
/// while framework chrome stays English.
///
/// It is a set of language *tags*, not `Locale` objects, because `zen_core` is framework-free
/// (no Flutter, no `dart:ui`). A Flutter consumer maps a tag with `Locale(tag)`; the generated
/// `supportedLocales` of each localized package is asserted against [shipped] by test, so a
/// package whose ARB set drifts from this declaration fails the suite rather than silently
/// claiming a language it has no strings for.
///
/// Adding a locale *to jZen* is: an ARB file per localized package, then the tag here. Adding one
/// *to an application* touches neither.
abstract final class ZenLocales {
  /// English - the fallback locale.
  static const String en = 'en';

  /// Ukrainian.
  static const String uk = 'uk';

  /// Every locale tag jZen's own packages ship messages for, in the order they are offered.
  ///
  /// The default for [resolve]'s `against`, and the floor an application builds on - never a
  /// ceiling on what it may support.
  static const List<String> shipped = [en, uk];

  /// The locale used when a requested tag is absent, blank, or unmatched.
  static const String fallback = en;

  /// Resolves a chosen or stored language tag against a set of locale tags, comparing only the
  /// primary subtag so `"uk-UA"` and `"uk_UA"` both match [uk]. Returns [fallback] for null,
  /// blank, or unmatched input - the same contract as the server's `ZenLocales.resolve`.
  ///
  /// `against` defaults to [shipped], which is what a *framework* caller means: "resolve this to
  /// something jZen has strings for". An **application** passes its own supported set, so a tag
  /// jZen ships nothing for survives resolution instead of being clamped to English.
  static String resolve(String? tag, {List<String> against = shipped}) {
    if (tag == null || tag.trim().isEmpty) return fallback;
    final primary = tag.trim().toLowerCase().split(RegExp('[-_]')).first;
    return against.contains(primary) ? primary : fallback;
  }
}
