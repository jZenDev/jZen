import 'package:test/test.dart';
import 'package:zen_core/src/result/zen_error.dart';
import 'package:zen_core/src/result/zen_result.dart';

void main() {
  group('ZenResult', () {
    test('ZenResult.ok returns ZenSuccess', () {
      const result = ZenResult.ok(42);
      expect(result, isA<ZenSuccess<int>>());
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.dataOrNull, 42);
      expect(result.errorOrNull, isNull);
    });

    test('ZenResult.err returns ZenFailure', () {
      const error = ZenValidationError('fail');
      const result = ZenResult<int>.err(error);
      expect(result, isA<ZenFailure<int>>());
      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.dataOrNull, isNull);
      expect(result.errorOrNull, error);
    });

    test('fold returns correct value for success', () {
      const result = ZenResult.ok('ok');
      final value = result.fold((data) => 'success: $data', (e) => 'fail');
      expect(value, 'success: ok');
    });

    test('fold returns correct value for failure', () {
      const error = ZenValidationError('fail');
      const result = ZenResult<String>.err(error);
      final value = result.fold(
        (data) => 'success',
        (e) => 'fail: ${e.message}',
      );
      expect(value, 'fail: fail');
    });

    test('ZenSuccess equality and hashCode', () {
      const a = ZenResult.ok(1);
      const b = ZenResult.ok(1);
      const c = ZenResult.ok(2);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('ZenFailure equality and hashCode', () {
      const err1 = ZenValidationError('fail');
      const err2 = ZenValidationError('fail');
      const a = ZenResult<int>.err(err1);
      const b = ZenResult<int>.err(err2);
      const c = ZenResult<int>.err(ZenValidationError('other'));
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
