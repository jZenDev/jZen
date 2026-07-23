import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

void main() {
  group('Value Objects', () {
    group('EmailAddress', () {
      test('validates correct email format', () {
        expect(EmailAddress.create('test@example.com').isSuccess, isTrue);
        expect(EmailAddress.create('user@domain.org').isSuccess, isTrue);
        expect(EmailAddress.create('name+tag@test.co.uk').isSuccess, isTrue);
      });

      test('rejects invalid email formats', () {
        expect(EmailAddress.create('invalid').isFailure, isTrue);
        expect(EmailAddress.create('').isFailure, isTrue);
        expect(EmailAddress.create('@example.com').isFailure, isTrue);
        expect(EmailAddress.create('test@').isFailure, isTrue);
        expect(EmailAddress.create('test').isFailure, isTrue);
      });

      test('toString returns email value', () {
        final email = EmailAddress.create('test@example.com').dataOrNull!;
        expect(email.toString(), 'test@example.com');
      });

      test('equality and hashCode work', () {
        final email1 = EmailAddress.create('test@example.com').dataOrNull!;
        final email2 = EmailAddress.create('test@example.com').dataOrNull!;
        final email3 = EmailAddress.create('other@example.com').dataOrNull!;

        expect(email1, equals(email2));
        expect(email1.hashCode, equals(email2.hashCode));
        expect(email1, isNot(equals(email3)));
      });
    });

    group('ZenLocale', () {
      test('validates language code only', () {
        expect(ZenLocale.create(languageCode: 'en').isSuccess, isTrue);
        expect(ZenLocale.create(languageCode: 'uk').isSuccess, isTrue);
      });

      test('validates language code with region', () {
        expect(
          ZenLocale.create(languageCode: 'en', regionCode: 'GB').isSuccess,
          isTrue,
        );
        expect(
          ZenLocale.create(languageCode: 'uk', regionCode: 'UA').isSuccess,
          isTrue,
        );
      });

      test('rejects invalid language codes', () {
        expect(ZenLocale.create(languageCode: 'E').isFailure, isTrue);
        expect(ZenLocale.create(languageCode: 'ENG').isFailure, isTrue);
        expect(
          ZenLocale.create(languageCode: 'EN').isFailure,
          isTrue,
        ); // Uppercase
        expect(ZenLocale.create(languageCode: '').isFailure, isTrue);
      });

      test('rejects invalid region codes', () {
        expect(
          ZenLocale.create(languageCode: 'en', regionCode: 'u').isFailure,
          isTrue,
        );
        expect(
          ZenLocale.create(languageCode: 'en', regionCode: 'us').isFailure,
          isTrue,
        ); // Lowercase
        expect(
          ZenLocale.create(languageCode: 'en', regionCode: 'USA').isFailure,
          isTrue,
        );
      });

      test('toString formats correctly', () {
        final locale1 = ZenLocale.create(languageCode: 'en').dataOrNull!;
        expect(locale1.toString(), 'en');

        final locale2 = ZenLocale.create(
          languageCode: 'uk',
          regionCode: 'UA',
        ).dataOrNull!;
        expect(locale2.toString(), 'uk_UA');
      });

      test('equality and hashCode work', () {
        final locale1 = ZenLocale.create(
          languageCode: 'uk',
          regionCode: 'UA',
        ).dataOrNull!;
        final locale2 = ZenLocale.create(
          languageCode: 'uk',
          regionCode: 'UA',
        ).dataOrNull!;
        final locale3 = ZenLocale.create(
          languageCode: 'en',
          regionCode: 'GB',
        ).dataOrNull!;

        expect(locale1, equals(locale2));
        expect(locale1.hashCode, equals(locale2.hashCode));
        expect(locale1, isNot(equals(locale3)));
      });
    });

    group('ZenTimestamp', () {
      test('creates from DateTime and forces UTC', () {
        final now = DateTime.now();
        final zt = ZenTimestamp.from(now);
        expect(zt.value.isUtc, isTrue);
      });

      test('now() creates current timestamp in UTC', () {
        final zt = ZenTimestamp.now();
        expect(zt.value.isUtc, isTrue);
      });

      test('fromMilliseconds creates timestamp correctly', () {
        final zt = ZenTimestamp.fromMilliseconds(1000000000000);
        expect(zt.millisecondsSinceEpoch, 1000000000000);
        expect(zt.value.isUtc, isTrue);
      });

      test('toString returns ISO8601 format', () {
        final zt = ZenTimestamp.fromMilliseconds(0);
        expect(zt.toString(), contains('1970-01-01'));
      });

      test('isBefore and isAfter comparisons work', () {
        final earlier = ZenTimestamp.fromMilliseconds(1000);
        final later = ZenTimestamp.fromMilliseconds(2000);

        expect(earlier.isBefore(later), isTrue);
        expect(later.isAfter(earlier), isTrue);
        expect(earlier.isAfter(later), isFalse);
        expect(later.isBefore(earlier), isFalse);
      });

      test('equality and hashCode work', () {
        final zt1 = ZenTimestamp.fromMilliseconds(1000);
        final zt2 = ZenTimestamp.fromMilliseconds(1000);
        final zt3 = ZenTimestamp.fromMilliseconds(2000);

        expect(zt1, equals(zt2));
        expect(zt1.hashCode, equals(zt2.hashCode));
        expect(zt1, isNot(equals(zt3)));
      });
    });

    group('UserId', () {
      test('validates non-empty strings', () {
        expect(UserId.create(' 123 ').isSuccess, isTrue);
        expect(UserId.create('abc').isSuccess, isTrue);
      });

      test('rejects empty and whitespace-only strings', () {
        expect(UserId.create('').isFailure, isTrue);
        expect(UserId.create('   ').isFailure, isTrue);
      });

      test('value is stored as-is without trimming', () {
        final userId = UserId.create('  test123  ').dataOrNull!;
        expect(userId.value, '  test123  ');
      });

      test('toString returns value', () {
        final userId = UserId.create('  test  ').dataOrNull!;
        expect(userId.toString(), '  test  ');
      });

      test('equality and hashCode work', () {
        final id1 = UserId.create('123').dataOrNull!;
        final id2 = UserId.create('123').dataOrNull!;
        final id3 = UserId.create('456').dataOrNull!;

        expect(id1, equals(id2));
        expect(id1.hashCode, equals(id2.hashCode));
        expect(id1, isNot(equals(id3)));
      });
    });
  });
}
