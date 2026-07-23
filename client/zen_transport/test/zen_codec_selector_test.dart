// The codec selector is compile-time, so it cannot be exercised by varying a value at
// runtime: it is proven by recompiling per ZEN_ENV/platform. The assertion below is derived
// from the same compile-time signals the selector reads, so a single test body is correct
// under every compile in the matrix:
//   - default (ZEN_ENV unset -> prd) on VM  -> protobuf
//   - --define=ZEN_ENV=dev                  -> json  (any platform)
//   - -p chrome (web)                       -> json
// Run the grid with `task test:client:matrix`.
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart' show zenIsDev;
import 'package:zen_transport/zen_transport.dart';

/// True on web (dart2js/dart2wasm), where all numbers are doubles, so `0 == 0.0` is
/// identical; false on the Dart VM. A compile-time platform signal for the test.
const bool kIsWeb = identical(0, 0.0);

void main() {
  group('selectDefaultCodec', () {
    test('returns a ZenTransportFormat', () {
      expect(selectDefaultCodec(), isA<ZenTransportFormat>());
    });

    test('is deterministic', () {
      expect(selectDefaultCodec(), selectDefaultCodec());
    });

    test('matches the compiled ZEN_ENV x platform matrix', () {
      final expected = zenIsDev
          ? ZenTransportFormat.json
          : (kIsWeb ? ZenTransportFormat.json : ZenTransportFormat.protobuf);
      expect(selectDefaultCodec(), expected);
    });

    test('dev mode always selects json regardless of platform', () {
      if (zenIsDev) {
        expect(selectDefaultCodec(), ZenTransportFormat.json);
      }
    });
  });
}
