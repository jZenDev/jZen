// Ported from
// ../DartZen/packages/dartzen_localization/test/zen_localization_exceptions_test.dart.
import 'package:test/test.dart';
import 'package:zen_localization/src/zen_localization_exceptions.dart';

void main() {
  group('ZenLocalizationException', () {
    test('toString returns correct message', () {
      final ex = _ZenLocalizationExceptionFake('error');
      expect(ex.toString(), 'ZenLocalizationException: error');
    });
  });

  group('MissingLocalizationKeyException', () {
    test('constructs with key and language', () {
      const ex = MissingLocalizationKeyException('foo', 'en');
      expect(ex.message, 'Missing key "foo" for language "en".');
      expect(ex.toString(), contains('Missing key "foo" for language "en".'));
    });
  });

  group('MissingLocalizationFileException', () {
    test('constructs with path', () {
      const ex = MissingLocalizationFileException('/foo/bar.json');
      expect(ex.message, contains('/foo/bar.json'));
      expect(ex.toString(), contains('/foo/bar.json'));
    });
  });

  group('InvalidLocalizationFormatException', () {
    test('constructs with path and reason', () {
      final ex = InvalidLocalizationFormatException(
        '/foo/bar.json',
        'bad json',
      );
      expect(ex.message, contains('/foo/bar.json'));
      expect(ex.toString(), contains('/foo/bar.json'));
    });
  });

  group('LocalizationInitializationException', () {
    test('constructs with message', () {
      const ex = LocalizationInitializationException('init failed');
      expect(ex.message, 'init failed');
      expect(ex.toString(), contains('init failed'));
    });
  });
}

// Fake for abstract class coverage
class _ZenLocalizationExceptionFake extends ZenLocalizationException {
  _ZenLocalizationExceptionFake(super.message);
}
