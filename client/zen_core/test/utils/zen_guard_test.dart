import 'package:test/test.dart';
import 'package:zen_core/src/result/zen_error.dart';
import 'package:zen_core/src/utils/zen_guard.dart';

void main() {
  group('ZenGuard', () {
    test('ensure returns ok for true', () {
      final result = ZenGuard.ensure(true, 'should not fail');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, isTrue);
    });

    test('ensure returns err for false', () {
      final result = ZenGuard.ensure(false, 'fail message');
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<ZenValidationError>());
      expect(result.errorOrNull?.message, 'fail message');
    });

    test('notNull returns ok for non-null', () {
      final result = ZenGuard.notNull(42, 'value');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 42);
    });

    test('notNull returns err for null', () {
      final result = ZenGuard.notNull(null, 'value');
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<ZenValidationError>());
      expect(result.errorOrNull?.message, 'value cannot be null');
    });

    test('notEmpty returns ok for non-empty', () {
      final result = ZenGuard.notEmpty('abc', 'field');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 'abc');
    });

    test('notEmpty returns err for empty', () {
      final result = ZenGuard.notEmpty('', 'field');
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<ZenValidationError>());
      expect(result.errorOrNull?.message, 'field cannot be empty');
    });
  });
}
