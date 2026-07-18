// Ported verbatim from
// ../DartZen/packages/dartzen_localization/lib/src/zen_localization_exceptions.dart.

/// Base exception for all localization errors.
abstract class ZenLocalizationException implements Exception {
  /// The error message.
  final String message;

  /// Creates a new [ZenLocalizationException].
  const ZenLocalizationException(this.message);

  @override
  String toString() => 'ZenLocalizationException: $message';
}

/// Thrown when a key is missing in Development mode.
class MissingLocalizationKeyException extends ZenLocalizationException {
  /// Creates an exception for missing [key] in [language].
  const MissingLocalizationKeyException(String key, String language)
    : super('Missing key "$key" for language "$language".');
}

/// Thrown when a localization file is missing.
class MissingLocalizationFileException extends ZenLocalizationException {
  /// Creates an exception for missing file at [path].
  const MissingLocalizationFileException(String path)
    : super('Localization file not found at "$path".');
}

/// Thrown when a localization file has invalid format.
class InvalidLocalizationFormatException extends ZenLocalizationException {
  /// Creates an exception for invalid format in [path].
  InvalidLocalizationFormatException(String path, dynamic content)
    : super(
        'Invalid format in "$path". Expected Map<String, dynamic>, got ${content.runtimeType}.',
      );
}

/// Thrown when the service is not properly initialized or used incorrectly.
class LocalizationInitializationException extends ZenLocalizationException {
  /// Creates an exception with the given [message].
  const LocalizationInitializationException(super.message);
}
