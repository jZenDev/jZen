// Ported verbatim from
// ../DartZen/packages/dartzen_localization/lib/src/zen_localization_config.dart.

/// Configuration for `ZenLocalizationService`.
class ZenLocalizationConfig {
  /// Base path for global localization files.
  ///
  /// Defaults to 'assets/l10n'.
  final String globalPath;

  /// Whether the application is running in production mode.
  ///
  /// In non-production mode (development/test), missing keys and files throw exceptions ("Fail Fast").
  /// In production mode, safe fallbacks are used.
  final bool isProduction;

  /// Creates a new configuration instance.
  ///
  /// [isProduction] must be passed explicitly. It defaults to `true` (Safe Fallback Mode).
  const ZenLocalizationConfig({
    this.globalPath = 'assets/l10n',
    this.isProduction = true,
  });
}
