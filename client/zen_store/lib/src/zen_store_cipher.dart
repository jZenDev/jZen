import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// The bytes every encrypted store file starts with, so a file that is not one is told apart
/// from one that fails to decrypt.
const List<int> _magic = [0x5a, 0x45, 0x4e, 0x31]; // "ZEN1"
const int _nonceLength = 12;
const int _macLength = 16;

/// AES-256-GCM over whole files: `ZEN1`, a fresh 12-byte nonce, the ciphertext, the 16-byte tag.
///
/// GCM authenticates as well as encrypts, so a damaged or altered file fails to decrypt instead
/// of decrypting to something else. Each file's name is bound in as associated data, so one
/// shard's ciphertext copied over another's fails too, rather than putting records where they do
/// not belong.
@internal
final class ZenStoreCipher {
  static final AesGcm _algorithm = AesGcm.with256bits();

  final SecretKey _key;

  ZenStoreCipher(List<int> key) : _key = SecretKey(List<int>.unmodifiable(key)) {
    if (key.length != 32) throw ArgumentError('a store key is 32 bytes, not ${key.length}');
  }

  Future<Uint8List> seal(List<int> clearText, String fileName) async {
    final box = await _algorithm.encrypt(clearText, secretKey: _key, aad: utf8.encode(fileName));
    return (BytesBuilder(copy: false)
          ..add(_magic)
          ..add(box.nonce)
          ..add(box.cipherText)
          ..add(box.mac.bytes))
        .takeBytes();
  }

  /// Throws [FormatException] when [sealed] is not a store file, or does not decrypt with this key
  /// under [fileName] — the wrong key, a damaged file, or one altered or moved.
  Future<List<int>> open(Uint8List sealed, String fileName) async {
    if (sealed.length < _magic.length + _nonceLength + _macLength || !_startsWithMagic(sealed)) {
      throw FormatException('$fileName is not an encrypted store file');
    }
    final nonce = sealed.sublist(_magic.length, _magic.length + _nonceLength);
    final cipherText = sealed.sublist(_magic.length + _nonceLength, sealed.length - _macLength);
    final mac = Mac(sealed.sublist(sealed.length - _macLength));
    try {
      return await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: _key,
        aad: utf8.encode(fileName),
      );
    } on SecretBoxAuthenticationError {
      throw FormatException(
        '$fileName does not decrypt with this key: the key is not the one it was written with, '
        'or the file was damaged or altered',
      );
    }
  }

  static bool _startsWithMagic(Uint8List bytes) {
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }
}
