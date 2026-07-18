// Ported verbatim from
// ../DartZen/packages/dartzen_localization/lib/src/zen_localization_cache.dart.

/// Internal cache for localization data.
class ZenLocalizationCache {
  // language -> { key -> value }
  final Map<String, Map<String, String>> _globalCache = {};

  // module -> language -> { key -> value }
  final Map<String, Map<String, Map<String, String>>> _moduleCache = {};

  /// Checks if global data for [language] is cached.
  bool hasGlobal(String language) => _globalCache.containsKey(language);

  /// Checks if module data for [module] and [language] is cached.
  bool hasModule(String module, String language) =>
      _moduleCache.containsKey(module) &&
      _moduleCache[module]!.containsKey(language);

  /// Stores global data.
  void setGlobal(String language, Map<String, String> data) {
    _globalCache[language] = data;
  }

  /// Stores module data.
  void setModule(String module, String language, Map<String, String> data) {
    _moduleCache.putIfAbsent(module, () => {})[language] = data;
  }

  /// Retrieves global messages for [language]. Returns empty map if not found.
  Map<String, String> getGlobal(String language) =>
      _globalCache[language] ?? const {};

  /// Retrieves module messages for [module] and [language]. Returns empty map if not found.
  Map<String, String> getModule(String module, String language) =>
      _moduleCache[module]?[language] ?? const {};

  /// Clears all caches.
  void clear() {
    _globalCache.clear();
    _moduleCache.clear();
  }
}
