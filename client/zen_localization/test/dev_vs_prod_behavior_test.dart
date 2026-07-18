// Ported from
// ../DartZen/packages/dartzen_localization/test/dev_vs_prod_behavior_test.dart.
import 'package:test/test.dart';
import 'package:zen_localization/zen_localization.dart';

class MockLoader implements ZenLocalizationLoader {
  final Map<String, String> files = {};

  @override
  Future<String> load(String path) async {
    if (files.containsKey(path)) {
      return files[path]!;
    }
    throw Exception('File not found: $path');
  }
}

void main() {
  group('Dev vs Production Behavior', () {
    late ZenLocalizationService devService;
    late ZenLocalizationService prodService;
    late MockLoader loader;

    setUp(() {
      loader = MockLoader();
      devService = ZenLocalizationService(
        config: const ZenLocalizationConfig(isProduction: false),
        loader: loader,
      );
      prodService = ZenLocalizationService(
        config: const ZenLocalizationConfig(),
        loader: loader,
      );
    });

    group('Development Mode (Fail Fast)', () {
      test('MISSING FILE throws exception', () async {
        // Did NOT populate loader
        expect(
          devService.loadGlobalMessages('en'),
          throwsA(isA<MissingLocalizationFileException>()),
        );
      });

      test('MISSING KEY throws exception', () async {
        loader.files['assets/l10n/zen.en.json'] = '{}';
        await devService.loadGlobalMessages('en');

        expect(
          () => devService.translate('missing', language: 'en'),
          throwsA(isA<MissingLocalizationKeyException>()),
        );
      });

      test('MISSING PARAM throws exception', () async {
        loader.files['assets/l10n/zen.en.json'] = '{"hi": "{name}"}';
        await devService.loadGlobalMessages('en');

        expect(
          () => devService.translate('hi', language: 'en', params: {}),
          throwsA(isA<LocalizationInitializationException>()),
        );
      });
    });

    group('Production Mode (Safe Fallback)', () {
      test('MISSING FILE logs error but does NOT throw', () async {
        // Should not throw
        await prodService.loadGlobalMessages('en');
        // Verify state? Cache is empty.
      });

      test('MISSING KEY returns key', () {
        expect(prodService.translate('missing', language: 'en'), 'missing');
      });

      test('MISSING PARAM returns empty/safe string', () async {
        loader.files['assets/l10n/en.json'] = '{"hi": "Hi {name}"}';
        await prodService.loadGlobalMessages('en');

        expect(
          prodService.translate('hi', language: 'en', params: {}),
          'Hi ', // Implementation returns '' for missing param val
        );
      });
    });
  });
}
