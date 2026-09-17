import 'package:test/test.dart';
import 'package:zen_core/src/logging/impl/strategy.dart';
import 'package:zen_core/src/logging/impl/strategy_io.dart' show getStrategy, ZenLoggerStrategyIO;
import 'package:zen_core/zen_core.dart';

class _LoggedCall {
  _LoggedCall(this.message, {required this.isError, this.origin});

  final String message;
  final bool isError;
  final String? origin;
}

class _FakeStrategy implements ZenLoggerStrategy {
  final calls = <_LoggedCall>[];

  @override
  void log(String message, {bool isError = false, String? origin}) {
    calls.add(_LoggedCall(message, isError: isError, origin: origin));
  }
}

void main() {
  group('ZenLogger', () {
    late _FakeStrategy strategy;
    late ZenLogger logger;

    setUp(() {
      strategy = _FakeStrategy();
      logger = ZenLogger.withStrategy(strategy);
    });

    test('debug prefixes the message with [DEBUG] and is not an error', () {
      logger.debug('debug message');

      expect(strategy.calls, hasLength(1));
      expect(strategy.calls.single.message, '[DEBUG] debug message');
      expect(strategy.calls.single.isError, isFalse);
    });

    test('info prefixes the message with [INFO]', () {
      logger.info('info message');

      expect(strategy.calls.single.message, '[INFO] info message');
      expect(strategy.calls.single.isError, isFalse);
    });

    test('warn prefixes the message with [WARN]', () {
      logger.warn('warn message');

      expect(strategy.calls.single.message, '[WARN] warn message');
      expect(strategy.calls.single.isError, isFalse);
    });

    test('error prefixes with [ERROR], marks isError, and appends error/stackTrace', () {
      final error = Exception('boom');
      final stackTrace = StackTrace.current;

      logger.error('error message', error: error, stackTrace: stackTrace);

      final call = strategy.calls.single;
      expect(call.isError, isTrue);
      expect(call.message, '[ERROR] error message\n$error\n$stackTrace');
    });

    test('error without error/stackTrace omits the extra lines', () {
      logger.error('simple error message');

      expect(strategy.calls.single.message, '[ERROR] simple error message');
    });

    test('internalData is appended after the formatted line', () {
      logger.info('with data', internalData: {'k': 1});

      expect(strategy.calls.single.message, '[INFO] with data\nData: {k: 1}');
    });

    test('ZenLogger.instance is a working default logger', () {
      expect(() => ZenLogger.instance.debug('smoke test'), returnsNormally);
    });
  });

  group('ZenLoggerStrategyIO', () {
    test('formatLine brackets the origin when given, and leaves the message plain otherwise', () {
      expect(ZenLoggerStrategyIO.formatLine('plain message'), 'plain message');
      expect(
        ZenLoggerStrategyIO.formatLine('origin message', origin: 'MyClass.method'),
        '[MyClass.method] origin message',
      );
    });

    test('getStrategy returns an IO strategy that logs without throwing', () {
      final strat = getStrategy();

      expect(strat, isA<ZenLoggerStrategyIO>());
      expect(() => strat.log('plain message'), returnsNormally);
      expect(() => strat.log('error message', isError: true, origin: 'Origin'), returnsNormally);
    });
  });
}
