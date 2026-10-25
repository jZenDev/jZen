import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// PBKDF2 rounds for a new PIN. A PIN has at most 10^8 values, so no hash makes a stolen copy
/// unguessable; what the rounds buy is time — each guess costs as much as an unlock does — and the
/// keychain, which keeps the item off backups and other devices, is the real wall.
const int zenPinIterations = 100000;

/// What is stored for a PIN: a salted PBKDF2-HMAC-SHA256 hash, never the PIN.
@internal
@immutable
final class ZenPinHash {
  final int iterations;
  final Uint8List salt;
  final Uint8List hash;

  const ZenPinHash(this.iterations, this.salt, this.hash);

  /// Hashes [pin] with a fresh salt, off the UI isolate: the rounds take long enough to drop
  /// frames.
  static Future<ZenPinHash> create(String pin, {int iterations = zenPinIterations}) async {
    final random = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
    return ZenPinHash(iterations, salt, await _derive(pin, salt, iterations));
  }

  /// Whether [pin] is the PIN this hash was made from, compared in constant time.
  Future<bool> matches(String pin) async {
    final candidate = await _derive(pin, salt, iterations);
    var difference = candidate.length ^ hash.length;
    for (var i = 0; i < candidate.length && i < hash.length; i++) {
      difference |= candidate[i] ^ hash[i];
    }
    return difference == 0;
  }

  String encode() => jsonEncode({
    'v': 1,
    'iterations': iterations,
    'salt': base64Encode(salt),
    'hash': base64Encode(hash),
  });

  /// Throws [FormatException] for anything that is not a stored PIN hash.
  static ZenPinHash decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, Object?> || json['v'] != 1) {
      throw const FormatException('not a stored PIN');
    }
    final iterations = json['iterations'];
    final salt = json['salt'];
    final hash = json['hash'];
    if (iterations is! int || iterations < 1 || salt is! String || hash is! String) {
      throw const FormatException('a stored PIN is malformed');
    }
    return ZenPinHash(iterations, base64Decode(salt), base64Decode(hash));
  }
}

/// PBKDF2 off the UI isolate. A hash of under a thousand rounds finishes in less time than
/// starting an isolate takes, so it runs in place — which is also what lets a widget test, whose
/// fake clock never delivers an isolate's reply, use a cheap lock.
Future<Uint8List> _derive(String pin, Uint8List salt, int iterations) {
  final password = utf8.encode(pin);
  if (iterations < 1000) return Future.value(zenPbkdf2(password, salt, iterations));
  return Isolate.run(() => zenPbkdf2(password, salt, iterations));
}

/// One 32-byte block of PBKDF2-HMAC-SHA256 (RFC 8018), which is all a 32-byte key needs.
@internal
Uint8List zenPbkdf2(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final key = Uint8List.fromList(block);
  for (var round = 1; round < iterations; round++) {
    block = hmac.convert(block).bytes;
    for (var i = 0; i < key.length; i++) {
      key[i] ^= block[i];
    }
  }
  return key;
}
