// Runs on package:test rather than flutter_test, because zen_core is framework-free.
import 'package:test/test.dart';
import 'package:zen_core/src/zen_constants.dart';

void main() {
  group('jZen Constants', () {
    test('zenPlatform returns correct value', () {
      // In test environment, should return the constant value
      expect(zenPlatform, isA<String>());
    });

    test('zenEnv returns correct value', () {
      expect(zenEnv, isA<String>());
    });

    test('zenIsPrd evaluates correctly', () {
      expect(zenIsPrd, isA<bool>());
      expect(zenIsDev, isA<bool>());
      // Cover both branches: zenIsPrd and zenIsDev
      if (zenEnv == 'prd') {
        expect(zenIsPrd, isTrue);
        expect(zenIsDev, isFalse);
      } else if (zenEnv == 'dev') {
        expect(zenIsPrd, isFalse);
        expect(zenIsDev, isTrue);
      } else {
        // Unknown env: both should be false
        expect(zenIsPrd, isFalse);
        expect(zenIsDev, isFalse);
      }
    });

    test('platform booleans are derived from zenPlatform', () {
      expect(zenIsMobile, zenIsAndroid || zenIsIOS);
      expect(zenIsDesktop, zenIsMacOS || zenIsLinux || zenIsWindows);
    });

    test('UI layout constants are defined', () {
      expect(zenMaxItemsMobile, 4);
      expect(zenNarrowWidth, 720);
    });
  });
}
