// Ported from ../DartZen/packages/dartzen_core/test/logging_test.dart, rewritten off
// flutter_test onto package:test (zen_core is framework-free).
import 'package:test/test.dart';
import 'package:zen_core/src/logging/zen_logger.dart';

void main() {
  group('ZenLogger', () {
    late ZenLogger logger;

    setUp(() {
      logger = ZenLogger.instance;
    });

    test('logs debug messages without error', () {
      expect(() => logger.debug('Debug message'), returnsNormally);
    });

    test('logs info messages without error', () {
      expect(() => logger.info('Info message'), returnsNormally);
    });

    test('logs warning messages without error', () {
      expect(() => logger.warn('Warning message'), returnsNormally);
    });

    test('logs error messages without error', () {
      expect(() => logger.error('Error message'), returnsNormally);
    });

    test('logs error with exception and stack trace', () {
      final exception = Exception('Test exception');
      final stackTrace = StackTrace.current;

      expect(
        () => logger.error(
          'Error with exception',
          error: exception,
          stackTrace: stackTrace,
        ),
        returnsNormally,
      );
    });

    test('logs messages with internal data', () {
      expect(
        () => logger.debug(
          'Debug with data',
          internalData: {'key': 'value', 'count': 42},
        ),
        returnsNormally,
      );

      expect(
        () => logger.info('Info with data', internalData: {'userId': '123'}),
        returnsNormally,
      );
    });
  });
}
