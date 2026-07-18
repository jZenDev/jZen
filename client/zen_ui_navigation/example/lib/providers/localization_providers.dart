import 'package:zen_localization/zen_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the localization service.
final localizationServiceProvider = Provider<ZenLocalizationService>((ref) {
  // Localization files are in lib/l10n/ declared as assets
  final config = ZenLocalizationConfig(globalPath: 'lib/l10n');
  return ZenLocalizationService(config: config);
});

/// Notifier for the current language code.
class LanguageNotifier extends Notifier<String> {
  @override
  String build() => 'en';

  void setLanguage(String language) {
    state = language;
  }
}

/// Provider for the current language code.
final languageProvider = NotifierProvider<LanguageNotifier, String>(
  LanguageNotifier.new,
);
