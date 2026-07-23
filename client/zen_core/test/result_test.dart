import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

void main() {
  group('ZenResult', () {
    test('ok returns ZenSuccess', () {
      const result = ZenResult.ok(42);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 42);
      expect(result, isA<ZenSuccess<int>>());
    });

    test('err returns ZenFailure', () {
      const result = ZenResult<int>.err(ZenValidationError('fail'));
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<ZenValidationError>());
      expect(result.errorOrNull?.message, 'fail');
      expect(result, isA<ZenFailure<int>>());
    });

    test('fold works correctly', () {
      const success = ZenResult.ok(10);
      final val1 = success.fold((data) => 'Got $data', (err) => 'Error');
      expect(val1, 'Got 10');

      const failure = ZenResult<int>.err(ZenValidationError('bad'));
      final val2 = failure.fold((data) => 'Got $data', (err) => err.message);
      expect(val2, 'bad');
    });

    test('ZenSuccess toString returns readable format', () {
      const result = ZenSuccess('test data');
      expect(result.toString(), 'ZenSuccess(test data)');
    });

    test('ZenSuccess equality and hashCode', () {
      const result1 = ZenSuccess(42);
      const result2 = ZenSuccess(42);
      const result3 = ZenSuccess(43);

      expect(result1, equals(result2));
      expect(result1.hashCode, equals(result2.hashCode));
      expect(result1, isNot(equals(result3)));
    });

    test('ZenFailure toString returns readable format', () {
      const result = ZenFailure<int>(ZenValidationError('bad input'));
      expect(result.toString(), contains('ZenFailure'));
      expect(result.toString(), contains('ZenValidationError'));
    });

    test('ZenFailure equality and hashCode', () {
      const error1 = ZenValidationError('error1');
      const error2 = ZenValidationError('error1');
      const error3 = ZenValidationError('error2');

      const result1 = ZenFailure<int>(error1);
      const result2 = ZenFailure<int>(error2);
      const result3 = ZenFailure<int>(error3);

      expect(result1, equals(result2));
      expect(result1.hashCode, equals(result2.hashCode));
      expect(result1, isNot(equals(result3)));
    });
  });

  group('ZenError', () {
    test('ZenValidationError holds data', () {
      const err = ZenValidationError(
        'Invalid input',
        internalData: {'field': 'email'},
      );
      expect(err.message, 'Invalid input');
      expect(err.internalData?['field'], 'email');
    });

    test('ZenNotFoundError holds data', () {
      const err = ZenNotFoundError('Missing', internalData: {'id': 1});
      expect(err.message, 'Missing');
      expect(err.internalData?['id'], 1);
    });

    test('ZenUnauthorizedError holds data', () {
      const err = ZenUnauthorizedError(
        'Access denied',
        internalData: {'userId': '123'},
      );
      expect(err.message, 'Access denied');
      expect(err.internalData?['userId'], '123');
    });

    test('ZenConflictError holds data', () {
      const err = ZenConflictError(
        'Duplicate entry',
        internalData: {'key': 'email'},
      );
      expect(err.message, 'Duplicate entry');
      expect(err.internalData?['key'], 'email');
    });

    test('ZenUnknownError holds data', () {
      const err = ZenUnknownError(
        'Something went wrong',
        internalData: {'code': 500},
      );
      expect(err.message, 'Something went wrong');
      expect(err.internalData?['code'], 500);
    });

    test('ZenError with stack trace', () {
      final stack = StackTrace.current;
      final err = ZenValidationError('error', stackTrace: stack);
      expect(err.stackTrace, equals(stack));
    });

    test('ZenError toString includes runtime type', () {
      const err = ZenValidationError('test message');
      expect(err.toString(), 'ZenValidationError: test message');
    });
  });
}
