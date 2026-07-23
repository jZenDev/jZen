// Proves proto messages round-trip in BOTH transport modes: Protobuf binary
// (writeToBuffer/mergeFromBuffer) and canonical proto3 JSON
// (toProto3Json/mergeFromProto3Json).
import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';
import 'package:zen_transport/zen_transport.dart';

void main() {
  group('ZenProtoCodec round-trips', () {
    for (final format in ZenTransportFormat.values) {
      group('${format.value} mode', () {
        test('HealthStatus survives encode -> decode', () {
          final original = HealthStatus(
            status: 'ok',
            service: 'zen-app',
            timestampMs: Int64(1752800000000),
          );
          final bytes = ZenProtoCodec.encode(original, format);
          final decoded = ZenProtoCodec.decode(bytes, format, HealthStatus.new);

          expect(decoded.status, 'ok');
          expect(decoded.service, 'zen-app');
          expect(decoded.timestampMs, Int64(1752800000000));
          expect(decoded, original);
        });

        test('PageRequest survives encode -> decode', () {
          final original = PageRequest(page: 2, size: 50, sort: 'createdAt desc');
          final bytes = ZenProtoCodec.encode(original, format);
          final decoded = ZenProtoCodec.decode(bytes, format, PageRequest.new);

          expect(decoded.page, 2);
          expect(decoded.size, 50);
          expect(decoded.sort, 'createdAt desc');
          expect(decoded, original);
        });

        test('ZenError (with field errors) survives encode -> decode', () {
          final original = ZenError(
            code: 'validation',
            message: 'Invalid input',
            fieldErrors: {'email': 'must not be empty'}.entries,
          );
          final bytes = ZenProtoCodec.encode(original, format);
          final decoded = ZenProtoCodec.decode(bytes, format, ZenError.new);

          expect(decoded.code, 'validation');
          expect(decoded.message, 'Invalid input');
          expect(decoded.fieldErrors['email'], 'must not be empty');
          expect(decoded, original);
        });
      });
    }

    test('json mode emits canonical proto3 JSON (camelCase field names)', () {
      final status = HealthStatus(
        status: 'ok',
        service: 'zen-app',
        timestampMs: Int64(1752800000000),
      );
      final bytes = ZenProtoCodec.encode(status, ZenTransportFormat.json);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      // proto3 JSON uses camelCase field names; int64 is a string.
      expect(json['status'], 'ok');
      expect(json['service'], 'zen-app');
      expect(json['timestampMs'], '1752800000000');
    });

    test('binary and json encodings differ but decode to the same message', () {
      final status = HealthStatus(status: 'ok', service: 'zen-app');
      final binary = ZenProtoCodec.encode(status, ZenTransportFormat.protobuf);
      final json = ZenProtoCodec.encode(status, ZenTransportFormat.json);

      expect(binary, isNot(equals(json)));
      expect(
        ZenProtoCodec.decode(binary, ZenTransportFormat.protobuf, HealthStatus.new),
        ZenProtoCodec.decode(json, ZenTransportFormat.json, HealthStatus.new),
      );
    });

    test('decode failure throws ZenTransportException', () {
      // Not valid JSON, and (usually) not a valid protobuf wire form.
      final garbage = utf8.encode('this is not a valid message {{{');
      expect(
        () => ZenProtoCodec.decode(
          garbage,
          ZenTransportFormat.json,
          HealthStatus.new,
        ),
        throwsA(isA<ZenTransportException>()),
      );
    });
  });
}
