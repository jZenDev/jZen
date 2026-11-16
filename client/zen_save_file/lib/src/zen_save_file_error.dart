/// A file the person chose to save could not be written. A cancel is not this: [zenSaveFile]
/// answers false for it.
final class ZenSaveFileError implements Exception {
  /// What went wrong, for a log or a message to the person.
  final String message;

  /// Creates the error.
  const ZenSaveFileError(this.message);

  @override
  String toString() => 'ZenSaveFileError: $message';
}
