// Ported from
// ../DartZen/packages/dartzen_localization/test/zen_localization_service_more_test.dart.
import 'package:test/test.dart';
import 'package:zen_localization/zen_localization.dart';

class _MockLoader2 implements ZenLocalizationLoader {
  final Map<String, String> files = {};

  @override
  Future<String> load(String path) async {
    if (files.containsKey(path)) return files[path]!;
    throw Exception('missing: $path');
  }
}

void main() {
  group('ZenLocalizationService additional branches', () {
    test('default loader and cache are created when not provided', () async {
      // Use default loader (platform-specific). It will attempt to read files
      // from disk and throw; we only assert that the default instances exist
      // and that calling loadGlobalMessages surfaces a MissingLocalizationFileException
      const cfg = ZenLocalizationConfig(isProduction: false);
      final svc = ZenLocalizationService(config: cfg);

      // Access cache getter (covers the getter line)
      expect(svc.cache, isNotNull);

      // Default loader should cause a MissingLocalizationFileException when file absent
      expect(
        () => svc.loadGlobalMessages('uk'),
        throwsA(isA<MissingLocalizationFileException>()),
      );
    });

    test(
      'default loader: loadModule throws MissingLocalizationFileException in dev',
      () async {
        const cfg = ZenLocalizationConfig(isProduction: false);
        final svc = ZenLocalizationService(config: cfg);

        expect(
          () =>
              svc.loadModuleMessages('auth', 'uk', modulePath: 'modules/auth'),
          throwsA(isA<MissingLocalizationFileException>()),
        );
      },
    );
    test(
      'dev: loadGlobal throws MissingLocalizationFileException on missing file',
      () async {
        final loader = _MockLoader2();
        const cfg = ZenLocalizationConfig(isProduction: false);
        final svc = ZenLocalizationService(config: cfg, loader: loader);

        expect(
          () => svc.loadGlobalMessages('uk'),
          throwsA(isA<MissingLocalizationFileException>()),
        );
      },
    );

    test(
      'dev: loadModule throws MissingLocalizationFileException on missing file',
      () async {
        final loader = _MockLoader2();
        const cfg = ZenLocalizationConfig(isProduction: false);
        final svc = ZenLocalizationService(config: cfg, loader: loader);

        expect(
          () =>
              svc.loadModuleMessages('auth', 'uk', modulePath: 'modules/auth'),
          throwsA(isA<MissingLocalizationFileException>()),
        );
      },
    );

    test(
      'prod: loadGlobal logs error and does not throw when loader fails',
      () async {
        final loader = _MockLoader2();
        const cfg = ZenLocalizationConfig();
        final svc = ZenLocalizationService(config: cfg, loader: loader);

        // Should not throw in production; cache remains empty
        await svc.loadGlobalMessages('uk');
        expect(svc.cache.hasGlobal('uk'), isFalse);
      },
    );

    test('interpolation converts non-string params to string', () async {
      final loader = _MockLoader2();
      loader.files['assets/l10n/zen.en.json'] = '{"count": "Count: {n}"}';
      const cfg = ZenLocalizationConfig(isProduction: false);
      final svc = ZenLocalizationService(config: cfg, loader: loader);

      await svc.loadGlobalMessages('en');
      final out = svc.translate('count', language: 'en', params: {'n': 42});
      expect(out, 'Count: 42');
    });

    test('does not reload global when cache already populated', () async {
      final loader = _MockLoader2();
      // loader will throw if called; pre-seed cache
      const cfg = ZenLocalizationConfig(isProduction: false);
      final svc = ZenLocalizationService(config: cfg, loader: loader);
      svc.cache.setGlobal('en', {'a': 'b'});

      // Should return early without calling loader
      await svc.loadGlobalMessages('en');
      expect(svc.translate('a', language: 'en'), 'b');
    });

    test(
      'does not reload module when module cache already populated',
      () async {
        final loader = _MockLoader2();
        const cfg = ZenLocalizationConfig(isProduction: false);
        final svc = ZenLocalizationService(config: cfg, loader: loader);
        svc.cache.setModule('auth', 'en', {'x': 'y'});

        await svc.loadModuleMessages('auth', 'en', modulePath: 'modules/auth');
        expect(svc.translate('x', language: 'en', module: 'auth'), 'y');
      },
    );

    test(
      'dev: loadModule rethrows ZenLocalizationException from parser',
      () async {
        final loader = _MockLoader2();
        // Provide an invalid JSON (non-map) for module file so parser throws
        loader.files['modules/auth/auth.en.json'] = '[1,2,3]';
        const cfg = ZenLocalizationConfig(isProduction: false);
        final svc = ZenLocalizationService(config: cfg, loader: loader);

        expect(
          () =>
              svc.loadModuleMessages('auth', 'en', modulePath: 'modules/auth'),
          throwsA(isA<InvalidLocalizationFormatException>()),
        );
      },
    );

    test(
      'parseAndValidateForTest throws for non-map and non-string values',
      () async {
        final svc = ZenLocalizationService(
          config: const ZenLocalizationConfig(isProduction: false),
        );
        // non-map
        expect(
          () => svc.parseAndValidateForTest('[1,2,3]', 'p'),
          throwsA(isA<InvalidLocalizationFormatException>()),
        );

        // non-string value
        expect(
          () => svc.parseAndValidateForTest('{"k": 123}', 'p'),
          throwsA(isA<InvalidLocalizationFormatException>()),
        );
      },
    );

    test('interpolateForTest throws in dev when param missing', () {
      final svc = ZenLocalizationService(
        config: const ZenLocalizationConfig(isProduction: false),
      );
      expect(
        () => svc.interpolateForTest('Hello {name}', {}),
        throwsA(isA<LocalizationInitializationException>()),
      );
    });

    test('translate fallback order exercises module+global en fallbacks', () async {
      final loader = _MockLoader2();
      const cfg = ZenLocalizationConfig(isProduction: false);
      final svc = ZenLocalizationService(config: cfg, loader: loader);

      // seed only 'en' entries
      svc.cache.setModule('auth', 'en', {'k': 'fromModuleEn'});
      svc.cache.setGlobal('en', {'k2': 'fromGlobalEn'});

      // module fallback: request 'uk' for module key -> should return module 'en'
      final res1 = svc.translate('k', language: 'uk', module: 'auth');
      expect(res1, 'fromModuleEn');

      // global fallback: request 'uk' for global key -> should return global 'en'
      final res2 = svc.translate('k2', language: 'uk');
      expect(res2, 'fromGlobalEn');
    });

    test(
      'prod: loadModule logs error and does not throw when loader fails',
      () async {
        final loader = _MockLoader2();
        const cfg = ZenLocalizationConfig();
        final svc = ZenLocalizationService(config: cfg, loader: loader);

        // Should not throw in production; cache remains empty for module
        await svc.loadModuleMessages('auth', 'en', modulePath: 'modules/auth');
        expect(svc.cache.hasModule('auth', 'en'), isFalse);
      },
    );
  });
}
