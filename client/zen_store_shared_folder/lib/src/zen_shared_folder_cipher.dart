import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// Why a file in the folder could not be opened.
@internal
final class ZenSharedFileException implements Exception {
  /// What is wrong, for a person debugging a sync service.
  final String message;

  /// True when the file is in a format a newer version of the app wrote.
  final bool newerVersion;

  ZenSharedFileException(this.message, {this.newerVersion = false});

  @override
  String toString() => message;
}

/// What a file in the folder holds once opened.
@internal
final class ZenSharedRecord {
  /// The record's name, `<collection>:<id>`.
  final String name;

  /// The record's encoded state, as `ZenStore.outgoing` produced it.
  final Uint8List payload;

  ZenSharedRecord(this.name, this.payload);
}

/// The folder's file format and its keys.
///
/// A file is `ZSF`, a format byte, a fresh 12-byte nonce, the ciphertext and the 16-byte GCM tag.
/// The ciphertext is `<name length: 2 bytes><record name><payload>`, so even the record's name
/// (collection and id) is hidden: the file is called by an HMAC of the name instead. The file's
/// path - `<device id>/<file name>` - is bound in as associated data, which is what makes a file
/// copied to another path, another device's directory or a "conflicted copy" name fail to open
/// instead of being merged as something it is not.
///
/// The encryption key and the file-name key are derived from the sync key with HKDF under distinct
/// labels, so one secret is never used as two kinds of key.
@internal
final class ZenSharedFolderCipher {
  /// The newest format this version reads and writes. A higher number was written by a newer
  /// version of the app.
  static const int format = 1;

  static const List<int> _magic = [0x5a, 0x53, 0x46]; // "ZSF"
  static const int _headerLength = 4;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static final AesGcm _aes = AesGcm.with256bits();
  static final Hmac _hmac = Hmac.sha256();

  final SecretKey _encryptionKey;
  final SecretKey _nameKey;

  ZenSharedFolderCipher._(this._encryptionKey, this._nameKey);

  /// Derives the folder's keys from [syncKey], 32 bytes.
  static Future<ZenSharedFolderCipher> derive(List<int> syncKey) async {
    if (syncKey.length != 32) {
      throw ArgumentError('a sync key is 32 bytes, not ${syncKey.length}');
    }
    final hkdf = Hkdf(hmac: _hmac, outputLength: 32);
    final root = SecretKey(List<int>.unmodifiable(syncKey));
    Future<SecretKey> subkey(String label) =>
        hkdf.deriveKey(secretKey: root, nonce: const [], info: utf8.encode(label));
    return ZenSharedFolderCipher._(
      await subkey('jzen-shared-folder/v1/encryption'),
      await subkey('jzen-shared-folder/v1/file-name'),
    );
  }

  /// The file name for a record: 64 hex characters of an HMAC of its name, then `.zen`. The same
  /// record always lands in the same file, and nobody without the sync key can tell which.
  Future<String> fileName(String recordName) async {
    final mac = await _hmac.calculateMac(utf8.encode(recordName), secretKey: _nameKey);
    return '${_hex(mac.bytes)}.zen';
  }

  /// Seals a record for the file at [path].
  Future<Uint8List> seal(String recordName, List<int> payload, String path) async {
    final name = utf8.encode(recordName);
    if (name.length > 0xffff) throw ArgumentError('a record name is at most 65535 bytes');
    final plain =
        (BytesBuilder(copy: false)
              ..addByte(name.length >> 8)
              ..addByte(name.length & 0xff)
              ..add(name)
              ..add(payload))
            .takeBytes();
    final box = await _aes.encrypt(plain, secretKey: _encryptionKey, aad: utf8.encode(path));
    return (BytesBuilder(copy: false)
          ..add(_magic)
          ..addByte(format)
          ..add(box.nonce)
          ..add(box.cipherText)
          ..add(box.mac.bytes))
        .takeBytes();
  }

  /// Opens the file at [path]. Throws [ZenSharedFileException] when it is not one of ours, was
  /// written by a newer version, is truncated or altered, was written under another key, or was
  /// moved from another path.
  Future<ZenSharedRecord> open(Uint8List sealed, String path) async {
    if (sealed.length < _headerLength || !_hasMagic(sealed)) {
      throw ZenSharedFileException('$path is not a jZen sync file');
    }
    if (sealed[3] > format) {
      throw ZenSharedFileException(
        '$path is format ${sealed[3]}; this version reads up to $format',
        newerVersion: true,
      );
    }
    if (sealed[3] == 0 || sealed.length < _headerLength + _nonceLength + _macLength + 2) {
      throw ZenSharedFileException('$path is truncated or not a jZen sync file');
    }
    final nonce = sealed.sublist(_headerLength, _headerLength + _nonceLength);
    final cipherText = sealed.sublist(_headerLength + _nonceLength, sealed.length - _macLength);
    final mac = Mac(sealed.sublist(sealed.length - _macLength));
    final List<int> plain;
    try {
      plain = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: _encryptionKey,
        aad: utf8.encode(path),
      );
    } on SecretBoxAuthenticationError {
      throw ZenSharedFileException(
        '$path does not decrypt: it is damaged or partly delivered, was written under another '
        'sync key, or was copied here from another path',
      );
    }
    final nameLength = (plain[0] << 8) | plain[1];
    if (plain.length < 2 + nameLength) {
      throw ZenSharedFileException('$path holds a malformed record');
    }
    final String name;
    try {
      name = utf8.decode(plain.sublist(2, 2 + nameLength));
    } on FormatException {
      throw ZenSharedFileException('$path holds a malformed record name');
    }
    return ZenSharedRecord(name, Uint8List.fromList(plain.sublist(2 + nameLength)));
  }

  static bool _hasMagic(Uint8List bytes) {
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
