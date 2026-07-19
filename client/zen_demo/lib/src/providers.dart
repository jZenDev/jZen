import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_localization/zen_localization.dart';

import 'demo_repository.dart';

/// The demo endpoint client. Overridden in [ProviderScope] with an instance sharing the session
/// http.Client (see main.dart), so it must be provided by the app.
final demoRepositoryProvider = Provider<DemoRepository>((ref) {
  throw UnimplementedError('demoRepositoryProvider must be overridden');
});

/// The current UI language code ({en, uk}), driving both the demo strings and the reused
/// identity/navigation packages, and sent to the server as Accept-Language.
class LanguageNotifier extends Notifier<String> {
  @override
  String build() => 'en';

  void setLanguage(String language) => state = language;
}

final languageProvider = NotifierProvider<LanguageNotifier, String>(
  LanguageNotifier.new,
);

/// Builds the localization service and loads the merged global bundles for both locales up
/// front (production-mode localization: one merged file per language). The UI shows a spinner
/// until this resolves. Loading both means switching languages is instant and offline.
final localizationServiceProvider = FutureProvider<ZenLocalizationService>((ref) async {
  final service = ZenLocalizationService(
    config: const ZenLocalizationConfig(globalPath: 'assets/l10n'),
  );
  await service.loadGlobalMessages('en');
  await service.loadGlobalMessages('uk');
  return service;
});
