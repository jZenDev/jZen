import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

void main() {
  group('ZenTry', () {
    test('catches exception in synchronous code', () {
      final result = ZenTry.call(() => throw Exception('oops'));
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('Exception: oops'));
      expect(result.errorOrNull, isA<ZenUnknownError>());
    });

    test('returns value on success', () {
      final result = ZenTry.call(() => 42);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 42);
    });

    test('callAsync catches exception', () async {
      final result = await ZenTry.callAsync(
        () async => throw Exception('async oops'),
      );
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('Exception: async oops'));
      expect(result.errorOrNull, isA<ZenUnknownError>());
    });

    test('callAsync returns value on success', () async {
      final result = await ZenTry.callAsync(() async => 'success');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 'success');
    });

    test('captures stack trace on error', () {
      final result = ZenTry.call(() => throw Exception('trace test'));
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.stackTrace, isNotNull);
    });
  });

  group('ZenGuard', () {
    test('ensure returns success when condition is true', () {
      final result = ZenGuard.ensure(true, 'ok');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, isTrue);
    });

    test('ensure returns failure when condition is false', () {
      final result = ZenGuard.ensure(false, 'fail');
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, 'fail');
      expect(result.errorOrNull, isA<ZenValidationError>());
    });

    test('notNull returns success when value is non-null', () {
      final result = ZenGuard.notNull('value', 'field');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 'value');
    });

    test('notNull returns failure when value is null', () {
      final result = ZenGuard.notNull(null, 'field');
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, 'field cannot be null');
      expect(result.errorOrNull, isA<ZenValidationError>());
    });

    test('notEmpty returns success when string is not empty', () {
      final result = ZenGuard.notEmpty('text', 'field');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 'text');
    });

    test('notEmpty returns failure when string is empty', () {
      final result = ZenGuard.notEmpty('', 'field');
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, 'field cannot be empty');
      expect(result.errorOrNull, isA<ZenValidationError>());
    });
  });
}
