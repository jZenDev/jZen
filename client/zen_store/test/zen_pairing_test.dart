import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

void main() {
  final key = List<int>.generate(32, (i) => (i * 37 + 11) & 255);
  final now = DateTime.utc(2026, 11, 14, 10);

  ZenPairingProblem? problemOf(ZenResult<List<int>> result) => switch (result) {
    ZenFailure(:final error) => (error as ZenPairingError).problem,
    ZenSuccess() => null,
  };

  String change(String text, int index, String to) =>
      text.substring(0, index) + to + text.substring(index + 1);

  test('a code round-trips the key', () {
    final offer = ZenPairing.offer(key, now: now);
    expect(ZenPairing.accept(offer.text, now: now).dataOrNull, key);
    expect(ZenPairing.accept(offer.qrData, now: now).dataOrNull, key);
  });

  test('the code is eleven groups of seven, and the offer says when it ends', () {
    final offer = ZenPairing.offer(key, now: now);
    final groups = offer.text.split('-');
    expect(groups, hasLength(11));
    expect(groups.every((g) => g.length == 7), isTrue);
    expect(offer.text, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z-]+$')));
    expect(offer.expiresAt, now.add(ZenPairing.lifetime));
    expect(offer.qrData, 'zenpair1:${offer.text}');
  });

  test('two offers of one key are not byte-identical once time moves', () {
    final later = ZenPairing.offer(key, now: now.add(const Duration(minutes: 3)));
    expect(later.text, isNot(ZenPairing.offer(key, now: now).text));
  });

  test('case, spaces, a missing dash and look-alike letters are forgiven', () {
    final text = ZenPairing.offer(key, now: now).text;
    final sloppy = text.toLowerCase().replaceAll('-', '  ');
    expect(ZenPairing.accept(sloppy, now: now).dataOrNull, key);
    expect(ZenPairing.accept(' ${text.replaceAll('-', '')} ', now: now).dataOrNull, key);
    final withZero = ZenPairing.offer(List.filled(32, 0), now: now).text;
    expect(
      ZenPairing.accept(withZero.replaceAll('0', 'o'), now: now).dataOrNull,
      List.filled(32, 0),
    );
  });

  test('a mistyped character is caught and its group named', () {
    final text = ZenPairing.offer(key, now: now).text;
    for (var index = 0; index < text.length; index++) {
      if (text[index] == '-') continue;
      final replacement = text[index] == 'A' ? 'B' : 'A';
      final result = ZenPairing.accept(change(text, index, replacement), now: now);
      expect(problemOf(result), ZenPairingProblem.mistyped, reason: 'at $index');
      expect(((result as ZenFailure).error as ZenPairingError).group, index ~/ 8 + 1);
    }
  });

  test('two neighbouring characters swapped are caught', () {
    final text = ZenPairing.offer(key, now: now).text;
    var caught = 0;
    var swaps = 0;
    for (var i = 0; i < text.length - 1; i++) {
      if (text[i] == '-' || text[i + 1] == '-' || text[i] == text[i + 1]) continue;
      final swapped = change(change(text, i, text[i + 1]), i + 1, text[i]);
      swaps++;
      if (problemOf(ZenPairing.accept(swapped, now: now)) != null) caught++;
    }
    expect(caught, swaps, reason: 'every adjacent swap in this code is detected');
  });

  test('groups typed out of order are caught as scrambled', () {
    final groups = ZenPairing.offer(key, now: now).text.split('-');
    final swapped = [groups[1], groups[0], ...groups.skip(2)].join('-');
    expect(problemOf(ZenPairing.accept(swapped, now: now)), ZenPairingProblem.scrambled);
  });

  test('a short, a long and a foreign entry are refused', () {
    final text = ZenPairing.offer(key, now: now).text;
    expect(
      problemOf(ZenPairing.accept(text.substring(0, text.length - 8), now: now)),
      ZenPairingProblem.wrongLength,
    );
    expect(problemOf(ZenPairing.accept('$text-ABCDEFG', now: now)), ZenPairingProblem.wrongLength);
    expect(problemOf(ZenPairing.accept('', now: now)), ZenPairingProblem.wrongLength);
    expect(problemOf(ZenPairing.accept('hello world!', now: now)), ZenPairingProblem.badCharacter);
  });

  test('an expired code is refused, a live one is not, and a slow clock is forgiven', () {
    final offer = ZenPairing.offer(key, now: now);
    final justBefore = offer.expiresAt.subtract(const Duration(seconds: 1));
    expect(ZenPairing.accept(offer.text, now: justBefore).dataOrNull, key);
    final withinTolerance = offer.expiresAt.add(const Duration(seconds: 30));
    expect(ZenPairing.accept(offer.text, now: withinTolerance).dataOrNull, key);
    final late = offer.expiresAt.add(ZenPairing.clockTolerance + const Duration(seconds: 1));
    expect(problemOf(ZenPairing.accept(offer.text, now: late)), ZenPairingProblem.expired);
  });

  test('a failure never repeats the code', () {
    final text = ZenPairing.offer(key, now: now).text;
    final result = ZenPairing.accept(change(text, 0, text[0] == 'A' ? 'B' : 'A'), now: now);
    final error = (result as ZenFailure).error;
    expect('$error ${error.message} ${error.internalData}', isNot(contains(text.substring(0, 6))));
  });

  test('a key of the wrong size cannot be offered', () {
    expect(() => ZenPairing.offer([1, 2, 3], now: now), throwsArgumentError);
  });
}
