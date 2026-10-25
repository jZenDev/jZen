import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_lock/src/state/zen_pin_hash.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

final class FakeOwner implements ZenOwnerCheck {
  bool passes;
  final reasons = <String>[];

  FakeOwner({this.passes = true});

  @override
  Future<ZenResult<void>> confirm(String reason) async {
    reasons.add(reason);
    return passes
        ? const ZenResult.ok(null)
        : const ZenResult.err(ZenUnauthorizedError('cancelled'));
  }
}

void main() {
  late ZenMemoryLockStorage storage;
  late FakeOwner owner;
  var clock = 0;

  setUp(() {
    storage = ZenMemoryLockStorage();
    owner = FakeOwner();
    clock = 1000000;
  });

  Future<ZenPinLock> load() async => (await ZenPinLock.load(
    storage: storage,
    owner: owner,
    now: () => clock,
    iterations: 10,
  )).dataOrNull!;

  test('PBKDF2-HMAC-SHA256 matches the published test vectors', () {
    String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    expect(
      hex(zenPbkdf2(utf8.encode('password'), utf8.encode('salt'), 1)),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      hex(zenPbkdf2(utf8.encode('password'), utf8.encode('salt'), 2)),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
  });

  test('off by default, so a new install opens straight into the app', () async {
    final lock = await load();

    expect(lock.isEnabled, isFalse);
    expect(lock.isLocked, isFalse);
  });

  test('with a PIN set, the app starts locked and the right PIN opens it', () async {
    await (await load()).enable('2468');
    final lock = await load();

    expect(lock.isLocked, isTrue);
    expect((await lock.unlock('1111')).errorOrNull, isA<ZenUnauthorizedError>());
    expect(lock.isLocked, isTrue);
    expect((await lock.unlock('2468')).isSuccess, isTrue);
    expect(lock.isLocked, isFalse);
  });

  test('only the hash is stored, never the PIN', () async {
    await (await load()).enable('2468');

    final stored = await storage.read('zen_pin_lock.hash');
    expect(stored, isNot(contains('2468')));
    expect(stored, contains('hash'));
  });

  test('a PIN is 4 to 8 digits', () async {
    final lock = await load();

    for (final pin in ['123', '123456789', '12a4', '']) {
      expect((await lock.enable(pin)).errorOrNull, isA<ZenValidationError>(), reason: pin);
    }
    expect((await lock.enable('12345678')).isSuccess, isTrue);
  });

  test('after five wrong PINs attempts are shut out, even for the right one, and it survives a '
      'restart', () async {
    await (await load()).enable('2468');
    var lock = await load();
    for (var i = 0; i < ZenPinLock.freeAttempts; i++) {
      await lock.unlock('0000');
    }
    expect(lock.retryAfter, const Duration(seconds: 30));

    lock = await load();
    expect((await lock.unlock('2468')).errorOrNull, isA<ZenPinLockedOutError>());
    expect(lock.isLocked, isTrue);

    clock += 30000;
    expect((await lock.unlock('2468')).isSuccess, isTrue);
  });

  test('each miss past the free attempts doubles the wait', () async {
    await (await load()).enable('2468');
    final lock = await load();
    for (var i = 0; i < ZenPinLock.freeAttempts; i++) {
      await lock.unlock('0000');
    }
    clock += 30000;
    await lock.unlock('0000');

    expect(lock.retryAfter, const Duration(seconds: 60));
  });

  test('changing or turning off the PIN needs the current one', () async {
    final lock = await load();
    await lock.enable('2468');

    expect((await lock.change('0000', '1357')).errorOrNull, isA<ZenUnauthorizedError>());
    expect((await lock.change('2468', '1357')).isSuccess, isTrue);
    expect((await lock.disable('2468')).errorOrNull, isA<ZenUnauthorizedError>());
    expect((await lock.disable('1357')).isSuccess, isTrue);
    expect(lock.isEnabled, isFalse);
  });

  test('a forgotten PIN is reset only through the device owner check', () async {
    await (await load()).enable('2468');
    final lock = await load();

    owner.passes = false;
    expect((await lock.recover('why')).isFailure, isTrue);
    expect(lock.isEnabled, isTrue);
    expect(lock.isLocked, isTrue);

    owner.passes = true;
    expect((await lock.recover('why')).isSuccess, isTrue);
    expect(owner.reasons, ['why', 'why']);
    expect(lock.isEnabled, isFalse);
    expect(lock.isLocked, isFalse);
  });

  test('an unreadable stored PIN fails the load instead of opening the app', () async {
    await storage.write('zen_pin_lock.hash', 'garbage');

    expect(
      (await ZenPinLock.load(storage: storage, owner: owner)).errorOrNull,
      isA<ZenUnknownError>(),
    );
  });

  test('lock() does nothing when no PIN is set', () async {
    final lock = await load();

    lock.lock();

    expect(lock.isLocked, isFalse);
  });
}
