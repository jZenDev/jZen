// Ported verbatim from
// ../DartZen/packages/dartzen_localization/lib/src/loader/loader_stub.dart.
import 'dart:async';

/// Interface for loading localization data.
abstract class ZenLocalizationLoaderImpl {
  /// Loads a string from the given [path].
  Future<String> load(String path);
}

/// Stub implementation throws error.
class ZenLocalizationLoaderStub implements ZenLocalizationLoaderImpl {
  @override
  Future<String> load(String path) {
    throw UnsupportedError('No suitable loader found for this platform.');
  }
}

/// Returns the correct loader implementation.
ZenLocalizationLoaderImpl getLoader() => ZenLocalizationLoaderStub();
