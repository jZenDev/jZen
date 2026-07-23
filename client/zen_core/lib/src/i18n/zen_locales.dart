/// The locales jZen ships, in one place, on the client side.
///
/// This is the Dart mirror of `zen.core.i18n.ZenLocales` (server/zen-core): the same set, the
/// same fallback, the same primary-subtag matching, so a language the server can speak is a
/// language the client can render and vice versa. The two declarations are deliberately
/// separate files rather than a generated pair - the set is three lines and changes once per
/// locale, whereas a generator would be exactly the "custom magic" the MANIFESTO forbids.
///
/// It is a set of language *tags*, not `Locale` objects, because `zen_core` is framework-free
/// (no Flutter, no `dart:ui`). A Flutter consumer maps a tag with `Locale(tag)`; the generated
/// `supportedLocales` of each localized package is asserted against [supported] by test, so a
/// package whose ARB set drifts from this declaration fails the suite rather than silently
/// rendering a language the server will not answer in.
///
/// Adding a locale is: an ARB file per localized package, then the tag here.
abstract final class ZenLocales {
  /// English - the fallback locale.
  static const String en = 'en';

  /// Ukrainian.
  static const String uk = 'uk';

  /// Every locale tag jZen ships messages for, in the order they are offered.
  static const List<String> supported = [en, uk];

  /// The locale used when a requested tag is absent, blank, or unsupported.
  static const String fallback = en;

  /// Resolves a chosen or stored language tag to a supported one, comparing only the primary
  /// subtag so `"uk-UA"` and `"uk_UA"` both match [uk]. Returns [fallback] for null, blank, or
  /// unsupported input - the same contract as the server's `ZenLocales.resolve`.
  static String resolve(String? tag) {
    if (tag == null || tag.trim().isEmpty) return fallback;
    final primary = tag.trim().toLowerCase().split(RegExp('[-_]')).first;
    return supported.contains(primary) ? primary : fallback;
  }
}
