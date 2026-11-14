import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:zen_core/zen_core.dart';

/// Why a typed or scanned pairing code was not accepted. The screens turn each into words.
enum ZenPairingProblem {
  /// Not the length of a pairing code; the person stopped early or typed too much.
  wrongLength,

  /// A character outside the alphabet, other than the look-alikes read as their twin.
  badCharacter,

  /// A group fails its check character: one character in it was mistyped. [ZenPairingError.group]
  /// says which.
  mistyped,

  /// Every group checks out, yet the whole does not: groups typed in the wrong order.
  scrambled,

  /// Written by a newer version of jZen, which this one cannot read.
  unsupportedVersion,

  /// Past its time; a new code has to be shown on the other device.
  expired,
}

/// A rejected pairing code. It carries what was wrong, never the code or any part of the key.
@immutable
final class ZenPairingError extends ZenError {
  /// What was wrong with the code.
  final ZenPairingProblem problem;

  /// For [ZenPairingProblem.mistyped], the 1-based number of the group to look at again.
  final int? group;

  /// Creates a [ZenPairingError].
  const ZenPairingError(this.problem, {this.group}) : super('the pairing code was not accepted');

  @override
  String toString() => 'ZenPairingError: ${problem.name}${group == null ? '' : ' (group $group)'}';
}

/// A code to show on a device that already holds the sync key, and when it stops working.
@immutable
final class ZenPairingOffer {
  /// The code as typed: groups of seven characters, a dash between them. It *is* the key — see
  /// [ZenPairing] — so it is shown, never logged, put in a URL or copied.
  final String text;

  /// The code as a QR code carries it (the typed code with a scheme in front).
  final String qrData;

  /// The moment after which a joining device refuses it.
  final DateTime expiresAt;

  /// Creates an offer.
  const ZenPairingOffer({required this.text, required this.qrData, required this.expiresAt});
}

/// The pairing format of ADR-075: how a device that holds the sync key hands it to a new one
/// with nothing between them but a screen and a person.
///
/// The code **carries the key itself**. Two devices that share no server and no network have no
/// other channel, and a short code that merely unlocked a blob stored somewhere would let
/// whoever holds the blob guess it offline. The consequence is stated plainly: anyone who photographs
/// the code while it is on screen holds the key, whatever its expiry. The expiry is honoured by a
/// joining device, so a code found later (a screenshot, a photo of the screen taken before it
/// was closed) is refused by an honest device; it does not stop an attacker who has the bytes.
/// The defence is the screen's, not the format's: the code appears only after the person asks
/// for it, goes away on cancel, on expiry and when the app leaves the foreground, and is never
/// written to a log, a URL or the clipboard.
///
/// Layout, before encoding (41 bytes): `version` (1) · `expires` (4, big-endian minutes since the
/// Unix epoch) · `key` (32) · `crc32` (4, over the first 37 bytes). Encoded as Crockford base32 —
/// `0-9` and `A-Z` without `I L O U`, 5 bits a character — 66 characters, in 11 groups of six
/// with a seventh, a check character, after each: 77 characters, typed in about a minute.
///
/// Typing is checked three ways. The check character (Luhn mod 32) catches any single mistyped
/// character in a group and nearly every swap of two neighbours, and names the group, so the
/// person re-reads six characters, not seventy-seven. The CRC catches groups typed out of order.
/// Case, spaces and dashes are ignored, and `O`, `I`, `L` read as `0`, `1`, `1`.
@immutable
abstract final class ZenPairing {
  /// How long a code is good for.
  static const Duration lifetime = Duration(minutes: 5);

  /// How far a joining device's clock may be ahead of the showing device's before a live code
  /// reads as expired; two devices rarely agree to the second.
  static const Duration clockTolerance = Duration(minutes: 1);

  /// What a QR code carries in front of the typed code, so a scanner reading some other QR code
  /// is told apart from one of ours.
  static const String qrScheme = 'zenpair1:';

  /// The number of data characters in a group.
  static const int groupSize = 6;

  static const int _version = 1;
  static const int _keyLength = 32;
  static const int _payloadLength = 41;
  static const int _dataChars = 66; // ceil(41 * 8 / 5)
  static const int _groups = _dataChars ~/ groupSize;
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// The length of a code once its separators are removed.
  static const int codeLength = _dataChars + _groups;

  /// Makes the code that hands [key] (32 bytes) to another device, good from [now].
  static ZenPairingOffer offer(List<int> key, {required DateTime now}) {
    if (key.length != _keyLength) {
      throw ArgumentError('a sync key is $_keyLength bytes, not ${key.length}');
    }
    if (key.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('a sync key is bytes, each 0 to 255');
    }
    final expiresAt = now.toUtc().add(lifetime);
    // Rounded up to the minute so the code shown is never good for less than it says.
    final minutes = (expiresAt.millisecondsSinceEpoch + 59999) ~/ 60000;
    final payload = Uint8List(_payloadLength);
    payload[0] = _version;
    ByteData.sublistView(payload).setUint32(1, minutes);
    payload.setRange(5, 5 + _keyLength, key);
    ByteData.sublistView(payload).setUint32(37, _crc32(payload, 37));
    final chars = _encode(payload);
    final groups = <String>[];
    for (var i = 0; i < _groups; i++) {
      final data = chars.substring(i * groupSize, (i + 1) * groupSize);
      groups.add('$data${_check(data)}');
    }
    final text = groups.join('-');
    return ZenPairingOffer(
      text: text,
      qrData: '$qrScheme$text',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(minutes * 60000, isUtc: true),
    );
  }

  /// Reads what a person typed or a scanner returned, at [now].
  ///
  /// Succeeds with the 32-byte sync key, or fails with a [ZenPairingError] naming what was wrong.
  /// The input is not kept, and no failure echoes any part of it.
  static ZenResult<List<int>> accept(String entered, {required DateTime now}) {
    var text = entered.trim();
    if (text.toLowerCase().startsWith(qrScheme)) text = text.substring(qrScheme.length);
    final chars = <int>[];
    for (final unit in text.toUpperCase().runes) {
      final ch = String.fromCharCode(unit);
      if (ch == ' ' || ch == '-' || ch == '–' || ch == '—') continue;
      final mapped = switch (ch) {
        'O' => '0',
        'I' || 'L' => '1',
        _ => ch,
      };
      final value = _alphabet.indexOf(mapped);
      if (value < 0) return const ZenFailure(ZenPairingError(ZenPairingProblem.badCharacter));
      chars.add(value);
    }
    if (chars.length != codeLength) {
      return const ZenFailure(ZenPairingError(ZenPairingProblem.wrongLength));
    }
    final data = StringBuffer();
    for (var g = 0; g < _groups; g++) {
      final start = g * (groupSize + 1);
      final group = chars.sublist(start, start + groupSize).map((v) => _alphabet[v]).join();
      if (_check(group) != _alphabet[chars[start + groupSize]]) {
        return ZenFailure(ZenPairingError(ZenPairingProblem.mistyped, group: g + 1));
      }
      data.write(group);
    }
    final payload = _decode(data.toString());
    final view = ByteData.sublistView(payload);
    if (view.getUint32(37) != _crc32(payload, 37)) {
      return const ZenFailure(ZenPairingError(ZenPairingProblem.scrambled));
    }
    if (payload[0] != _version) {
      return const ZenFailure(ZenPairingError(ZenPairingProblem.unsupportedVersion));
    }
    final expiresMs = view.getUint32(1) * 60000;
    if (now.toUtc().millisecondsSinceEpoch - clockTolerance.inMilliseconds > expiresMs) {
      return const ZenFailure(ZenPairingError(ZenPairingProblem.expired));
    }
    return ZenSuccess(List<int>.unmodifiable(payload.sublist(5, 5 + _keyLength)));
  }

  static String _encode(Uint8List bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  static Uint8List _decode(String chars) {
    final out = Uint8List(_payloadLength);
    var buffer = 0;
    var bits = 0;
    var index = 0;
    for (var i = 0; i < chars.length && index < _payloadLength; i++) {
      buffer = (buffer << 5) | _alphabet.indexOf(chars[i]);
      bits += 5;
      if (bits >= 8) {
        out[index++] = (buffer >> (bits - 8)) & 255;
        bits -= 8;
        buffer &= (1 << bits) - 1;
      }
    }
    return out;
  }

  /// Luhn mod 32 over [group]'s characters: the character that makes the group sum to 0.
  static String _check(String group) {
    var factor = 2;
    var sum = 0;
    for (var i = group.length - 1; i >= 0; i--) {
      var addend = factor * _alphabet.indexOf(group[i]);
      factor = factor == 2 ? 1 : 2;
      addend = (addend ~/ 32) + (addend % 32);
      sum += addend;
    }
    return _alphabet[(32 - (sum % 32)) % 32];
  }

  static int _crc32(Uint8List bytes, int length) {
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < length; i++) {
      crc ^= bytes[i];
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}
