import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

void main() {
  group('ZenTry', () {
    test('call returns success on normal execution', () {
      final r = ZenTry.call(() => 42);
      expect(r.isSuccess, isTrue);
      expect((r as ZenSuccess).data, 42);
    });

    test('call returns failure when throwing', () {
      final r = ZenTry.call<int>(() => throw Exception('boom'));
      expect(r.isFailure, isTrue);
      expect((r as ZenFailure).error, isA<ZenUnknownError>());
      // ensure the implementation path that attaches a stack trace is exercised
      expect((r as ZenFailure).error.stackTrace, isNotNull);
    });

    test('callAsync returns success and failure properly', () async {
      final r1 = await ZenTry.callAsync(() async => 'ok');
      expect(r1.isSuccess, isTrue);
      expect((r1 as ZenSuccess).data, 'ok');

      final r2 = await ZenTry.callAsync<String>(
        () async => throw Exception('err'),
      );
      expect(r2.isFailure, isTrue);
      expect((r2 as ZenFailure).error, isA<ZenUnknownError>());
    });
  });

  group('ZenGuard', () {
    test('ensure true returns success, false returns validation error', () {
      final ok = ZenGuard.ensure(true, 'ok');
      expect(ok.isSuccess, isTrue);
      final no = ZenGuard.ensure(false, 'bad');
      expect(no.isFailure, isTrue);
      expect((no as ZenFailure).error, isA<ZenValidationError>());
    });

    test('notNull handles null and non-null', () {
      final r = ZenGuard.notNull('x', 'name');
      expect(r.isSuccess, isTrue);
      final n = ZenGuard.notNull(null, 'n');
      expect(n.isFailure, isTrue);
      // also call notEmpty with empty to hit that branch explicitly
      final e = ZenGuard.notEmpty('', 's');
      expect(e.isFailure, isTrue);
    });

    test('notEmpty handles empty and non-empty', () {
      final r = ZenGuard.notEmpty('hi', 's');
      expect(r.isSuccess, isTrue);
      final e = ZenGuard.notEmpty('', 's');
      expect(e.isFailure, isTrue);
    });
  });
}
