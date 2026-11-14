import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:zen_core/zen_core.dart';

import 'zen_lock_storage.dart';
import 'zen_owner_check.dart';
import 'zen_pin_hash.dart';
import 'zen_pin_locked_out_error.dart';

/// Erases this device's copy of the app's data and its key; see [ZenPinLock.load].
typedef ZenDeviceErase = Future<ZenResult<void>> Function();

/// How a forgotten PIN can be reset on a device.
enum ZenPinRecovery {
  /// The device's own passcode, Face ID, Touch ID or Windows Hello confirms the owner.
  ownerCheck,

  /// The device cannot confirm its owner, so the person erases this device's copy and re-syncs it.
  eraseDeviceCopy,

  /// No way: no PIN is set, or the device cannot check its owner and the app gave no eraser.
  none,
}

/// An optional PIN that closes a Local application, whose data has no sign-in in front of it.
///
/// Off until the person turns it on ([enable]). When on, the app starts locked, and `ZenLockGate`
/// locks it again after it has been in the background a while. Wrong PINs are counted across
/// restarts: from the [freeAttempts]th miss on, each one shuts attempts out for longer (30 seconds,
/// doubling, at most an hour), so guessing a four-digit PIN by hand is not practical. A forgotten
/// PIN is reset through the device's own owner check ([recover]) or, where the device has none,
/// by erasing this device's copy ([recoverByErasing]); never by a bare reset.
final class ZenPinLock extends ChangeNotifier {
  /// The fewest digits a PIN may have.
  static const int minDigits = 4;

  /// The most digits a PIN may have.
  static const int maxDigits = 8;

  /// Wrong PINs allowed before attempts are shut out for a while.
  static const int freeAttempts = 5;

  static const String _hashKey = 'zen_pin_lock.hash';
  static const String _failuresKey = 'zen_pin_lock.failures';
  static final RegExp _digits = RegExp(r'^[0-9]+$');

  final ZenLockStorage _storage;
  final ZenOwnerCheck _owner;
  final ZenDeviceErase? _erase;
  final int Function() _now;
  final int _iterations;

  ZenPinHash? _hash;
  bool _locked;
  int _failures;
  int _shutUntil;

  ZenPinLock._(
    this._storage,
    this._owner,
    this._erase,
    this._now,
    this._iterations,
    this._hash,
    this._failures,
    this._shutUntil,
  ) : _locked = _hash != null;

  /// Reads the lock's state. Fails if the stored state cannot be read — and an unreadable PIN is
  /// not taken to mean "no PIN": that would open the app to anyone who could damage the item.
  ///
  /// [eraseDeviceCopy] is what "Forgot PIN?" does on a device that cannot check its owner (Linux;
  /// see [ZenOwnerCheck.isAvailable]): it deletes this device's copy of the app's data and its
  /// key, which the other devices then re-sync. Without it such a device offers no recovery.
  /// It must be idempotent — if it succeeds and removing the PIN then fails, a retry calls it
  /// again — and it must delete locally, not through the sync engine: a deletion record would
  /// propagate and erase the data on the other devices too.
  ///
  /// [now] and [iterations] exist for tests.
  static Future<ZenResult<ZenPinLock>> load({
    ZenLockStorage? storage,
    ZenOwnerCheck? owner,
    ZenDeviceErase? eraseDeviceCopy,
    int Function()? now,
    @visibleForTesting int iterations = zenPinIterations,
  }) async {
    final store = storage ?? ZenSecureLockStorage();
    try {
      final hashText = await store.read(_hashKey);
      final failuresText = await store.read(_failuresKey);
      final failures = failuresText == null ? null : jsonDecode(failuresText);
      if (failures != null &&
          (failures is! Map<String, Object?> ||
              failures['count'] is! int ||
              failures['until'] is! int)) {
        throw const FormatException('the stored attempt count is malformed');
      }
      return ZenResult.ok(
        ZenPinLock._(
          store,
          owner ?? ZenDeviceOwnerCheck(),
          eraseDeviceCopy,
          now ?? () => DateTime.now().millisecondsSinceEpoch,
          iterations,
          hashText == null ? null : ZenPinHash.decode(hashText),
          (failures as Map<String, Object?>?)?['count'] as int? ?? 0,
          failures?['until'] as int? ?? 0,
        ),
      );
    } on Object catch (e, stack) {
      return ZenResult.err(ZenUnknownError('The app lock cannot be read: $e', stackTrace: stack));
    }
  }

  /// Whether a PIN is set.
  bool get isEnabled => _hash != null;

  /// Whether the app is closed until the PIN is entered.
  bool get isLocked => _locked;

  /// How long until another attempt is accepted, or null when one is accepted now.
  Duration? get retryAfter {
    final wait = _shutUntil - _now();
    return wait > 0 ? Duration(milliseconds: wait) : null;
  }

  /// Closes the app until the PIN is entered. Does nothing when no PIN is set.
  void lock() {
    if (!isEnabled || _locked) return;
    _locked = true;
    notifyListeners();
  }

  /// Opens the app if [pin] is right. A wrong PIN is a [ZenUnauthorizedError]; while attempts are
  /// shut out, every attempt is a [ZenPinLockedOutError] and [pin] is not even checked.
  Future<ZenResult<void>> unlock(String pin) async {
    final hash = _hash;
    if (hash == null || !_locked) return const ZenResult.ok(null);
    final checked = await _check(hash, pin);
    if (checked case ZenFailure(:final error)) return ZenResult.err(error);
    _locked = false;
    notifyListeners();
    return const ZenResult.ok(null);
  }

  /// Turns the lock on with [pin]. Fails if a PIN is already set; [change] replaces one.
  Future<ZenResult<void>> enable(String pin) async {
    if (isEnabled) return const ZenResult.err(ZenConflictError('A PIN is already set.'));
    if (validate(pin) case final error?) return ZenResult.err(error);
    return _store(() async => _setHash(await ZenPinHash.create(pin, iterations: _iterations)));
  }

  /// Replaces the PIN, once [current] proves the person knows it.
  Future<ZenResult<void>> change(String current, String next) async {
    final hash = _hash;
    if (hash == null) return const ZenResult.err(ZenNotFoundError('No PIN is set.'));
    if (validate(next) case final error?) return ZenResult.err(error);
    final checked = await _check(hash, current);
    if (checked case ZenFailure(:final error)) return ZenResult.err(error);
    return _store(() async => _setHash(await ZenPinHash.create(next, iterations: _iterations)));
  }

  /// Turns the lock off, once [current] proves the person knows the PIN.
  Future<ZenResult<void>> disable(String current) async {
    final hash = _hash;
    if (hash == null) return const ZenResult.ok(null);
    final checked = await _check(hash, current);
    if (checked case ZenFailure(:final error)) return ZenResult.err(error);
    return _store(() async => _setHash(null));
  }

  /// For a forgotten PIN: once the device's owner check passes, the PIN is removed and the app
  /// opens, so the person can set a new one. [reason] is shown in the system prompt.
  Future<ZenResult<void>> recover(String reason) async {
    if (!isEnabled) return const ZenResult.ok(null);
    final confirmed = await _owner.confirm(reason);
    if (confirmed case ZenFailure(:final error)) return ZenResult.err(error);
    return _store(() async {
      await _recordFailures(0, 0);
      await _setHash(null);
    });
  }

  /// How a forgotten PIN can be reset on this device, or the error if that could not be found out
  /// (the screen then says so and lets the person retry, rather than guessing).
  Future<ZenResult<ZenPinRecovery>> recoveryOption() async {
    if (!isEnabled) return const ZenResult.ok(ZenPinRecovery.none);
    final available = await _owner.isAvailable();
    return switch (available) {
      ZenFailure(:final error) => ZenResult.err(error),
      ZenSuccess(:final data) when data => const ZenResult.ok(ZenPinRecovery.ownerCheck),
      ZenSuccess() => ZenResult.ok(
        _erase != null ? ZenPinRecovery.eraseDeviceCopy : ZenPinRecovery.none,
      ),
    };
  }

  /// For a forgotten PIN on a device that cannot check its owner: erases this device's copy of the
  /// app's data through the `eraseDeviceCopy` given to [load], then removes the PIN. The PIN goes
  /// only after the data is gone, so a failed erase leaves the app locked, never open with data.
  Future<ZenResult<void>> recoverByErasing() async {
    final erase = _erase;
    if (!isEnabled) return const ZenResult.ok(null);
    if (erase == null) {
      return const ZenResult.err(ZenUnauthorizedError('This device has no way to reset the PIN.'));
    }
    final ZenResult<void> erased;
    try {
      erased = await erase();
    } on Object catch (e, stack) {
      return ZenResult.err(
        ZenUnknownError('This device\'s copy was not erased: $e', stackTrace: stack),
      );
    }
    if (erased case ZenFailure(:final error)) return ZenResult.err(error);
    return _store(() async {
      await _recordFailures(0, 0);
      await _setHash(null);
    });
  }

  /// Why [pin] cannot be a PIN, or null when it can.
  static ZenValidationError? validate(String pin) {
    if (pin.length < minDigits || pin.length > maxDigits || !_digits.hasMatch(pin)) {
      return const ZenValidationError('A PIN is 4 to 8 digits.');
    }
    return null;
  }

  Future<ZenResult<void>> _check(ZenPinHash hash, String pin) async {
    if (retryAfter case final wait?) return ZenResult.err(ZenPinLockedOutError(wait));
    if (await hash.matches(pin)) {
      if (_failures > 0) {
        final reset = await _store(() => _recordFailures(0, 0));
        if (reset case ZenFailure(:final error)) return ZenResult.err(error);
      }
      return const ZenResult.ok(null);
    }
    final failures = _failures + 1;
    final over = failures - freeAttempts;
    final shutFor = over < 0 ? 0 : math.min(30000 * math.pow(2, over).toInt(), 3600000);
    final recorded = await _store(
      () => _recordFailures(failures, shutFor == 0 ? 0 : _now() + shutFor),
    );
    if (recorded case ZenFailure(:final error)) return ZenResult.err(error);
    return const ZenResult.err(ZenUnauthorizedError('The PIN is wrong.'));
  }

  Future<void> _setHash(ZenPinHash? hash) async {
    if (hash == null) {
      await _storage.delete(_hashKey);
    } else {
      await _storage.write(_hashKey, hash.encode());
    }
    _hash = hash;
    _locked = false;
    notifyListeners();
  }

  Future<void> _recordFailures(int count, int until) async {
    await _storage.write(_failuresKey, jsonEncode({'count': count, 'until': until}));
    _failures = count;
    _shutUntil = until;
  }

  Future<ZenResult<void>> _store(Future<void> Function() action) async {
    try {
      await action();
      return const ZenResult.ok(null);
    } on Object catch (e, stack) {
      return ZenResult.err(ZenUnknownError('The app lock cannot be saved: $e', stackTrace: stack));
    }
  }
}
