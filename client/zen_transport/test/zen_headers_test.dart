// Pins the X-Zen-Transport header name and its two format values against the server's.
import 'package:test/test.dart';
import 'package:zen_transport/zen_transport.dart';

void main() {
  group('ZenTransportFormat', () {
    test('header name is X-Zen-Transport', () {
      expect(zenTransportHeaderName, 'X-Zen-Transport');
    });

    test('enum values map to header strings', () {
      expect(ZenTransportFormat.json.value, 'json');
      expect(ZenTransportFormat.protobuf.value, 'protobuf');
    });

    test('parse handles valid values', () {
      expect(ZenTransportFormat.parse('json'), ZenTransportFormat.json);
      expect(ZenTransportFormat.parse('protobuf'), ZenTransportFormat.protobuf);
    });

    test('parse is case-insensitive', () {
      expect(ZenTransportFormat.parse('JSON'), ZenTransportFormat.json);
      expect(ZenTransportFormat.parse('Protobuf'), ZenTransportFormat.protobuf);
      expect(ZenTransportFormat.parse('PROTOBUF'), ZenTransportFormat.protobuf);
    });

    test('parse throws ZenTransportException on unknown values', () {
      expect(() => ZenTransportFormat.parse('xml'), throwsA(isA<ZenTransportException>()));
      expect(() => ZenTransportFormat.parse(''), throwsA(isA<ZenTransportException>()));
    });

    test('parse exception message names the bad value', () {
      try {
        ZenTransportFormat.parse('invalid');
        fail('expected throw');
      } on ZenTransportException catch (e) {
        expect(e.message, contains('Invalid transport format: "invalid"'));
      }
    });
  });
}
