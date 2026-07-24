// The codec seam operates on typed protobuf messages, never an untyped `Object?`: binary via
// the protobuf runtime (writeToBuffer / mergeFromBuffer), JSON via canonical proto3 JSON
// (toProto3Json / mergeFromProto3Json). Canonical proto3 JSON is what the Quarkus server's
// JsonFormat and openapi-typescript also emit, so all three languages agree on the JSON
// shape (docs/architecture/BLUEPRINT.md).
import 'dart:convert';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';

import 'zen_transport_exception.dart';
import 'zen_transport_header.dart';

/// Encodes and decodes protobuf messages for a given [ZenTransportFormat].
class ZenProtoCodec {
  const ZenProtoCodec._();

  /// Encodes [message] into wire bytes using [format].
  ///
  /// - [ZenTransportFormat.protobuf]: protobuf binary (`writeToBuffer`).
  /// - [ZenTransportFormat.json]: canonical proto3 JSON (`toProto3Json`), UTF-8 encoded.
  static Uint8List encode(GeneratedMessage message, ZenTransportFormat format) {
    try {
      switch (format) {
        case ZenTransportFormat.protobuf:
          return message.writeToBuffer();
        case ZenTransportFormat.json:
          return Uint8List.fromList(utf8.encode(jsonEncode(message.toProto3Json())));
      }
    } catch (e) {
      throw ZenTransportException('Failed to encode message: $e');
    }
  }

  /// Decodes wire [bytes] into a message of type [T] using [format].
  ///
  /// [createEmpty] returns a fresh, empty message instance to merge into (protobuf has no
  /// generic static factory, so the caller supplies the constructor tear-off, e.g.
  /// `HealthStatus.new`).
  ///
  /// - [ZenTransportFormat.protobuf]: `mergeFromBuffer`.
  /// - [ZenTransportFormat.json]: canonical proto3 JSON (`mergeFromProto3Json`).
  static T decode<T extends GeneratedMessage>(
    Uint8List bytes,
    ZenTransportFormat format,
    T Function() createEmpty,
  ) {
    try {
      switch (format) {
        case ZenTransportFormat.protobuf:
          return createEmpty()..mergeFromBuffer(bytes);
        case ZenTransportFormat.json:
          return createEmpty()..mergeFromProto3Json(jsonDecode(utf8.decode(bytes)));
      }
    } catch (e) {
      throw ZenTransportException('Failed to decode message: $e');
    }
  }
}
