/// Exception thrown by zen_transport operations.
///
/// This is the only exception type used throughout the transport layer.
/// It provides a descriptive message about what went wrong during
/// serialization, deserialization, or transport operations.
class ZenTransportException implements Exception {
  /// Creates a transport exception with the given [message].
  const ZenTransportException(this.message);

  /// A descriptive error message.
  final String message;

  @override
  String toString() => 'ZenTransportException: $message';
}
