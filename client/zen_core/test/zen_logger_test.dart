import 'package:test/test.dart';
import 'package:zen_core/src/logging/impl/strategy_io.dart'
    show getStrategy, ZenLoggerStrategyIO;
import 'package:zen_core/zen_core.dart';

void main() {
  group('ZenLogger', () {
    test('default logger methods run without throwing', () {
      // These calls exercise zen_logger.dart paths (debug/info/warn/error)
      ZenLogger.instance.debug('debug message');
      ZenLogger.instance.info('info message');
      ZenLogger.instance.warn('warn message');
      ZenLogger.instance.error(
        'error message',
        error: Exception('e'),
        stackTrace: StackTrace.current,
      );
      // also exercise error without error/stackTrace
      ZenLogger.instance.error('simple error message');
    });

    test('internalData and strategy origin branches', () {
      ZenLogger.instance.info('with data', internalData: {'k': 1});

      // Exercise strategy IO origin formatting and isError branch.
      final strat = getStrategy();
      strat.log('origin message', origin: 'MyClass.method');
      strat.log('origin error', isError: true, origin: 'MyClass.method');
      // also exercise null origin (plain) and error flag without origin
      strat.log('plain message');
      strat.log('error without origin', isError: true);
      // Directly construct the IO strategy and call both branches to ensure
      // implementation lines are hit
      final impl = ZenLoggerStrategyIO();
      impl.log('impl plain');
      impl.log('impl error', isError: true, origin: 'Imp');
    });
  });
}
