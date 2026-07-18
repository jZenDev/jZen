// Ported from
// ../DartZen/packages/dartzen_localization/lib/src/zen_localization_service.dart.
// The donor's dev-file prefix 'dartzen.' is renamed 'zen.'.
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:zen_core/zen_core.dart';

import 'zen_localization_cache.dart';
import 'zen_localization_config.dart';
import 'zen_localization_exceptions.dart';
import 'zen_localization_loader.dart';

/// Core service for jZen localization.
class ZenLocalizationService {
  /// Exposes the internal cache for testing and advanced use.
  ZenLocalizationCache get cache => _cache;

  /// The configuration for this service.
  final ZenLocalizationConfig config;

  /// The loader used to read localization files.
  final ZenLocalizationLoader _loader;

  /// The cache used to store loaded localization data.
  final ZenLocalizationCache _cache;

  /// Creates a new service with the given [config].
  ZenLocalizationService({
    required this.config,
    ZenLocalizationLoader? loader,
    ZenLocalizationCache? cache,
  }) : _loader = loader ?? ZenLocalizationLoader(),
       _cache = cache ?? ZenLocalizationCache();

  /// Loads global messages for the specified [language].
  ///
  /// In Production: Loads the merged `$language.json` file containing all messages.
  /// In Development: Reads `zen.$language.json` from `config.globalPath`.
  Future<void> loadGlobalMessages(String language) async {
    if (_cache.hasGlobal(language)) return;

    final fileName = config.isProduction
        ? '$language.json'
        : 'zen.$language.json';
    final path = p.join(config.globalPath, fileName);

    try {
      final content = await _loader.load(path);
      final json = _parseAndValidate(content, path);
      _cache.setGlobal(language, json);
    } catch (e, st) {
      if (!config.isProduction) {
        if (e is ZenLocalizationException) rethrow;
        throw MissingLocalizationFileException(path);
      }
      ZenLogger.instance.error(
        'Failed to load global messages for $language: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Loads messages for a specific [module] and [language].
  ///
  /// In Production: No-op (assumes messages are merged into global bundle).
  /// In Development: Reads `[module].[language].json` from the provided [modulePath].
  Future<void> loadModuleMessages(
    String module,
    String language, {
    required String modulePath,
  }) async {
    if (config.isProduction) return; // Production uses merged global file
    if (_cache.hasModule(module, language)) return;

    final fileName = '$module.$language.json';
    final path = p.join(modulePath, fileName);

    try {
      final content = await _loader.load(path);
      final json = _parseAndValidate(content, path);
      _cache.setModule(module, language, json);
    } catch (e, st) {
      if (!config.isProduction) {
        if (e is ZenLocalizationException) rethrow;
        throw MissingLocalizationFileException(path);
      }
      ZenLogger.instance.error(
        'Failed to load module messages for $module ($language): $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Translates [key] for the given [language].
  ///
  /// Lookup Order:
  /// 1. Module bundle (if [module] provided)
  /// 2. Global bundle
  /// 3. Fallback language ("en") - Module (if loaded)
  /// 4. Fallback language ("en") - Global (if loaded)
  ///
  /// Throws [MissingLocalizationKeyException] in dev if not found.
  /// Returns [key] in production if not found.
  String translate(
    String key, {
    required String language,
    String? module,
    Map<String, dynamic> params = const {},
  }) {
    String? template;

    // 1. Module bundle
    if (module != null) {
      template = _cache.getModule(module, language)[key];
    }

    // 2. Global bundle
    template ??= _cache.getGlobal(language)[key];

    // 3. Fallback "en" (Module)
    if (template == null && language != 'en') {
      if (module != null) {
        template = _cache.getModule(module, 'en')[key];
      }
    }

    // 4. Fallback "en" (Global)
    if (template == null && language != 'en') {
      template = _cache.getGlobal('en')[key];
    }

    if (template == null) {
      if (config.isProduction) {
        return key;
      }
      throw MissingLocalizationKeyException(key, language);
    }

    return _interpolate(template, params);
  }

  Map<String, String> _parseAndValidate(String content, String path) {
    final dynamic decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw InvalidLocalizationFormatException(path, decoded);
    }

    final result = <String, String>{};
    for (final entry in decoded.entries) {
      if (entry.value is! String) {
        // Strict flat JSON: value must be string.
        throw InvalidLocalizationFormatException(
          path,
          'Key "${entry.key}" has non-string value.',
        );
      }
      result[entry.key] = entry.value as String;
    }
    return result;
  }

  String _interpolate(String template, Map<String, dynamic> params) =>
      template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) {
        final paramName = match.group(1)!;
        final value = params[paramName];
        if (value == null) {
          if (config.isProduction) {
            return ''; // Safe fallback
          }
          throw LocalizationInitializationException(
            'Missing parameter "{$paramName}" in translation.',
          );
        }
        return value.toString();
      });

  /// Exposed for tests to validate parsing behavior directly.
  @visibleForTesting
  Map<String, String> parseAndValidateForTest(String content, String path) =>
      _parseAndValidate(content, path);

  /// Exposed for tests to validate interpolation directly.
  @visibleForTesting
  String interpolateForTest(String template, Map<String, dynamic> params) =>
      _interpolate(template, params);
}
