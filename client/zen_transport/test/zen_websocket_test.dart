// Uses an in-memory fake channel to exercise the typed send/receive path (no envelope).
import 'dart:async';
import 'dart:typed_data';

import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:zen_transport/zen_transport.dart';

class _FakeSink implements WebSocketSink {
  final List<dynamic> added = [];
  int? closeCode;
  String? closeReason;

  @override
  void add(dynamic data) => added.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    this.closeCode = closeCode;
    this.closeReason = closeReason;
  }

  @override
  Future<dynamic> get done => Future<void>.value();
}

class _FakeChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _FakeChannel(this._incoming);

  final Stream<dynamic> _incoming;
  final _FakeSink _sink = _FakeSink();

  @override
  Stream<dynamic> get stream => _incoming;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => _sink.closeCode;

  @override
  String? get closeReason => _sink.closeReason;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();
}

void main() {
  group('ZenWebSocket.decodeMessage', () {
    test('decodes a Uint8List frame', () {
      final bytes = ZenProtoCodec.encode(
        HealthStatus(status: 'ok'),
        ZenTransportFormat.protobuf,
      );
      final decoded = ZenWebSocket.decodeMessage(
        bytes,
        ZenTransportFormat.protobuf,
        HealthStatus.new,
      );
      expect(decoded.status, 'ok');
    });

    test('decodes a List<int> frame', () {
      final bytes = ZenProtoCodec.encode(
        HealthStatus(status: 'ok'),
        ZenTransportFormat.protobuf,
      );
      final decoded = ZenWebSocket.decodeMessage(
        bytes.toList(), // List<int>, not Uint8List
        ZenTransportFormat.protobuf,
        HealthStatus.new,
      );
      expect(decoded.status, 'ok');
    });

    test('throws FormatException on an unexpected frame type', () {
      expect(
        () => ZenWebSocket.decodeMessage(
          'not-bytes',
          ZenTransportFormat.protobuf,
          HealthStatus.new,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ZenWebSocket', () {
    test('send encodes the message onto the sink', () {
      final channel = _FakeChannel(const Stream<dynamic>.empty());
      final ws = ZenWebSocket.withChannel(
        channel,
        format: ZenTransportFormat.protobuf,
      );

      ws.send(HealthStatus(status: 'ok', service: 'zen-demo-server'));

      final sent = channel.sink as _FakeSink;
      expect(sent.added, hasLength(1));
      final decoded = ZenProtoCodec.decode(
        sent.added.single as Uint8List,
        ZenTransportFormat.protobuf,
        HealthStatus.new,
      );
      expect(decoded.service, 'zen-demo-server');
    });

    test('responses decodes incoming frames into typed messages', () async {
      final incoming = ZenProtoCodec.encode(
        HealthStatus(status: 'ok', service: 'zen-demo-server'),
        ZenTransportFormat.protobuf,
      );
      final channel = _FakeChannel(Stream<dynamic>.value(incoming));
      final ws = ZenWebSocket.withChannel(
        channel,
        format: ZenTransportFormat.protobuf,
      );

      final first = await ws.responses(HealthStatus.new).first;
      expect(first.status, 'ok');
      expect(first.service, 'zen-demo-server');
    });

    test('close delegates the code and reason to the sink', () async {
      final channel = _FakeChannel(const Stream<dynamic>.empty());
      final ws = ZenWebSocket.withChannel(
        channel,
        format: ZenTransportFormat.protobuf,
      );

      await ws.close(1000, 'bye');
      expect(channel.closeCode, 1000);
      expect(channel.closeReason, 'bye');
    });
  });
}
