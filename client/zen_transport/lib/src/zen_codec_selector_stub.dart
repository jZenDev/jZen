import 'zen_transport_header.dart';

/// Stub implementation for unsupported platforms.
///
/// This should never be called in practice due to conditional imports.
ZenTransportFormat selectPlatformCodec() {
  throw UnsupportedError('Platform not supported');
}
