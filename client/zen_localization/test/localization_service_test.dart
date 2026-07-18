// Ported from
// ../DartZen/packages/dartzen_localization/test/localization_service_test.dart.
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
  group('ZenLocalizationService', () {
    late ZenLocalizationService service;
    late MockLoader loader;
    late ZenLocalizationConfig devConfig;

    setUp(() {
      loader = MockLoader();
      devConfig = const ZenLocalizationConfig(isProduction: false);
      service = ZenLocalizationService(config: devConfig, loader: loader);
    });

    test('loads global messages successfully', () async {
      loader.files['assets/l10n/zen.en.json'] = '{"app.title": "jZen"}';

      await service.loadGlobalMessages('en');
      final result = service.translate('app.title', language: 'en');
      expect(result, 'jZen');
    });

    test('loads module messages successfully', () async {
      loader.files['modules/auth/auth.en.json'] = '{"login.btn": "Login"}';

      await service.loadModuleMessages(
        'auth',
        'en',
        modulePath: 'modules/auth',
      );
      final result = service.translate(
        'login.btn',
        language: 'en',
        module: 'auth',
      );
      expect(result, 'Login');
    });

    test('lookup order: Module -> Global', () async {
      loader.files['assets/l10n/zen.en.json'] = '{"shared.key": "Global"}';
      loader.files['modules/auth/auth.en.json'] = '{"shared.key": "Module"}';

      await service.loadGlobalMessages('en');
      await service.loadModuleMessages(
        'auth',
        'en',
        modulePath: 'modules/auth',
      );

      // Should prefer Module
      expect(
        service.translate('shared.key', language: 'en', module: 'auth'),
        'Module',
      );

      // Without module, should use Global
      expect(service.translate('shared.key', language: 'en'), 'Global');
    });

    test('lookup fallback: dev throws on missing key', () {
      expect(
        () => service.translate('missing.key', language: 'en'),
        throwsA(isA<MissingLocalizationKeyException>()),
      );
    });

    test('interpolation works', () async {
      loader.files['assets/l10n/zen.en.json'] = '{"hello": "Hello, {name}!"}';
      await service.loadGlobalMessages('en');

      expect(
        service.translate('hello', language: 'en', params: {'name': 'World'}),
        'Hello, World!',
      );
    });

    test('dev mode throws on missing params', () async {
      loader.files['assets/l10n/zen.en.json'] = '{"hello": "Hello, {name}!"}';
      await service.loadGlobalMessages('en');

      expect(
        () => service.translate('hello', language: 'en', params: {}),
        throwsA(isA<LocalizationInitializationException>()),
      );
    });

    test('_parseAndValidate throws on non-map JSON', () async {
      loader.files['assets/l10n/zen.en.json'] = '[1,2,3]';
      expect(
        service.loadGlobalMessages('en'),
        throwsA(isA<InvalidLocalizationFormatException>()),
      );
    });

    test('_parseAndValidate throws on non-string value', () async {
      loader.files['assets/l10n/zen.en.json'] = '{"foo": 123}';
      expect(
        service.loadGlobalMessages('en'),
        throwsA(isA<InvalidLocalizationFormatException>()),
      );
    });
  });

  group('Production Behavior', () {
    late ZenLocalizationService service;
    late MockLoader loader;
    late ZenLocalizationConfig prodConfig;

    setUp(() {
      loader = MockLoader();
      prodConfig = const ZenLocalizationConfig();
      service = ZenLocalizationService(config: prodConfig, loader: loader);
    });

    test('missing key returns key instead of throwing', () {
      expect(service.translate('missing.key', language: 'en'), 'missing.key');
    });

    test('missing param returns empty string instead of throwing', () async {
      loader.files['assets/l10n/en.json'] = '{"hello": "Hello, {name}!"}';
      await service.loadGlobalMessages('en');

      expect(
        service.translate('hello', language: 'en', params: {}),
        'Hello, !', // Based on implementation: returns '' for missing param
      );
    });

    test('loadGlobal uses merged filename in production', () async {
      // In prod, loads 'en.json' not 'zen.en.json'
      loader.files['assets/l10n/en.json'] = '{"merged": "true"}';

      await service.loadGlobalMessages('en');
      expect(service.translate('merged', language: 'en'), 'true');
    });

    test('loadModule is no-op in production', () async {
      // Even if file exists, it shouldn't be loaded/used if isProduction=true logic prevents it
      // But wait, if loadModule returns early, the cache is empty.
      // translate falls back to Global.
      // So if Global has it (merged), it works.
      // If Global doesn't have it, it returns key.

      loader.files['assets/l10n/en.json'] = '{"module.key": "MergedVal"}';
      loader.files['modules/auth/auth.en.json'] = '{"module.key": "ModuleVal"}';

      await service.loadGlobalMessages('en');
      await service.loadModuleMessages(
        'auth',
        'en',
        modulePath: 'modules/auth',
      );

      // Should get 'MergedVal' from Global, ignoring Module file
      expect(
        service.translate('module.key', language: 'en', module: 'auth'),
        'MergedVal',
      );
    });
  });
}
