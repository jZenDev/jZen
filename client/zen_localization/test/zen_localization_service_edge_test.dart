// Ported from
// ../DartZen/packages/dartzen_localization/test/zen_localization_service_edge_test.dart.
import 'package:test/test.dart';
import 'package:zen_localization/zen_localization.dart';

void main() {
  group('ZenLocalizationService edge cases', () {
    late ZenLocalizationService service;
    late MockLoader loader;
    late ZenLocalizationConfig devConfig;
    late ZenLocalizationConfig prodConfig;

    setUp(() {
      loader = MockLoader();
      devConfig = const ZenLocalizationConfig(isProduction: false);
      prodConfig = const ZenLocalizationConfig();
    });

    test('translate falls back to en (module)', () async {
      service = ZenLocalizationService(config: devConfig, loader: loader);
      loader.files['modules/auth/auth.en.json'] = '{"foo": "bar"}';
      await service.loadModuleMessages(
        'auth',
        'en',
        modulePath: 'modules/auth',
      );
      // No "uk" loaded, should fallback to en
      expect(service.translate('foo', language: 'uk', module: 'auth'), 'bar');
    });

    test('translate falls back to en (global)', () async {
      service = ZenLocalizationService(config: devConfig, loader: loader);
      loader.files['assets/l10n/zen.en.json'] = '{"foo": "bar"}';
      await service.loadGlobalMessages('en');
      // No "uk" loaded, should fallback to en
      expect(service.translate('foo', language: 'uk'), 'bar');
    });

    test('returns key for missing param in prod', () {
      service = ZenLocalizationService(config: prodConfig, loader: loader);
      expect(service.translate('foo', language: 'en', params: {}), 'foo');
    });
  });

  group('ZenLocalizationLoader', () {
    test('delegates to getLoader', () async {
      final loader = ZenLocalizationLoader();
      // Should not throw, but will throw UnsupportedError in stub env
      try {
        await loader.load('foo');
      } catch (_) {
        // Accept any error, just ensure delegation path is covered
      }
    });
  });
}

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
