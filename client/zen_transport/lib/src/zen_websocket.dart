// Re-architected from
// ../DartZen/packages/dartzen_transport/lib/src/internal/websocket/zen_websocket.dart.
// Sends and receives typed protobuf messages (no {id,status,data,error} envelope) via
// ZenProtoCodec, with the wire format chosen by selectDefaultCodec().
import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'zen_codec_selector.dart';
import 'zen_proto_codec.dart';
import 'zen_transport_header.dart';

/// A minimal WebSocket helper for jZen transport.
///
/// Provides basic WebSocket connectivity with automatic codec selection for sending and
/// receiving typed protobuf messages. This is a simple utility without reconnection or
/// streaming logic.
class ZenWebSocket {
  /// Creates a WebSocket connection to the given [uri].
  ///
  /// Optionally specify a [format] to override automatic codec selection.
  ZenWebSocket(Uri uri, {ZenTransportFormat? format})
    : _format = format ?? selectDefaultCodec(),
      _channel = WebSocketChannel.connect(uri);

  /// Alternative constructor that accepts an existing [WebSocketChannel].
  ///
  /// Useful for tests or when a channel is created externally and should be injected.
  @visibleForTesting
  ZenWebSocket.withChannel(
    WebSocketChannel channel, {
    ZenTransportFormat? format,
  }) : _format = format ?? selectDefaultCodec(),
       _channel = channel;

  final ZenTransportFormat _format;
  final WebSocketChannel _channel;

  /// The transport format being used.
  ZenTransportFormat get format => _format;

  /// Stream of incoming messages of type [T].
  ///
  /// [createEmpty] is the message constructor tear-off (e.g. `HealthStatus.new`).
  Stream<T> responses<T extends GeneratedMessage>(T Function() createEmpty) =>
      _channel.stream.map(
        (message) => decodeMessage(message, _format, createEmpty),
      );

  /// Decodes a single WebSocket [message] into a message of type [T].
  ///
  /// Handles both `Uint8List` and `List<int>` binary frames. Exposed for tests.
  @visibleForTesting
  static T decodeMessage<T extends GeneratedMessage>(
    dynamic message,
    ZenTransportFormat format,
    T Function() createEmpty,
  ) {
    if (message is Uint8List) {
      return ZenProtoCodec.decode(message, format, createEmpty);
    }
    if (message is List<int>) {
      return ZenProtoCodec.decode(
        Uint8List.fromList(message),
        format,
        createEmpty,
      );
    }
    throw FormatException('Unexpected message type: ${message.runtimeType}');
  }

  /// Sends a typed proto [message] through the WebSocket.
  void send(GeneratedMessage message) =>
      _channel.sink.add(ZenProtoCodec.encode(message, _format));

  /// Closes the WebSocket connection.
  Future<void> close([int? closeCode, String? closeReason]) =>
      _channel.sink.close(closeCode, closeReason);
}
