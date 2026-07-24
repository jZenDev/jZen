import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

void main() {
  group('BaseResponse', () {
    test('success factory produces success response', () {
      final r = BaseResponse<Map<String, int>>.success(const {'a': 1}, message: 'OK');
      expect(r.success, isTrue);
      expect(r.data, {'a': 1});
      expect(r.message, 'OK');
    });

    test('failure factory produces failure response with explicit code', () {
      final r = BaseResponse<void>.failure('failed', errorCode: 'ERR_01');
      expect(r.success, isFalse);
      expect(r.errorCode, 'ERR_01');
      expect(r.message, 'failed');
    });

    test('fromError maps known zen errors to codes', () {
      const v = ZenValidationError('bad');
      final r1 = BaseResponse<void>.fromError(v);
      expect(r1.errorCode, 'VALIDATION_ERROR');

      const nf = ZenNotFoundError('notfound');
      final r2 = BaseResponse<void>.fromError(nf);
      expect(r2.errorCode, 'NOT_FOUND_ERROR');

      const una = ZenUnauthorizedError('no');
      final r3 = BaseResponse<void>.fromError(una);
      expect(r3.errorCode, 'UNAUTHORIZED_ERROR');

      const conf = ZenConflictError('conf');
      final r4 = BaseResponse<void>.fromError(conf);
      expect(r4.errorCode, 'CONFLICT_ERROR');
    });

    test('toString includes key fields', () {
      final s = BaseResponse.success('ok');
      final str = s.toString();
      expect(str, contains('BaseResponse'));
      expect(str, contains('success: true'));
    });
  });
}
