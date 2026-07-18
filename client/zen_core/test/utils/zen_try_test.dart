// Ported from ../DartZen/packages/dartzen_core/test/utils/zen_try_test.dart.
import 'package:test/test.dart';
import 'package:zen_core/src/result/zen_error.dart';
import 'package:zen_core/src/result/zen_result.dart';
import 'package:zen_core/src/utils/zen_try.dart';

void main() {
  group('ZenTry', () {
    test('call returns ZenSuccess for non-throwing block', () {
      final result = ZenTry.call(() => 42);
      expect(result, isA<ZenSuccess<int>>());
      expect(result.dataOrNull, 42);
      expect(result.isSuccess, isTrue);
    });

    test('call returns ZenFailure for throwing block', () {
      final result = ZenTry.call(() => throw Exception('fail'));
      expect(result, isA<ZenFailure<int>>());
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<ZenUnknownError>());
      expect(result.errorOrNull?.message, contains('fail'));
    });

    test('callAsync returns ZenSuccess for non-throwing async block', () async {
      final result = await ZenTry.callAsync(() async => 99);
      expect(result, isA<ZenSuccess<int>>());
      expect(result.dataOrNull, 99);
      expect(result.isSuccess, isTrue);
    });

    test('callAsync returns ZenFailure for throwing async block', () async {
      final result = await ZenTry.callAsync(
        () async => throw Exception('fail async'),
      );
      expect(result, isA<ZenFailure<int>>());
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<ZenUnknownError>());
      expect(result.errorOrNull?.message, contains('fail async'));
    });
  });
}
