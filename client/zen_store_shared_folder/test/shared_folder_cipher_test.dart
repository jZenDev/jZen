import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zen_store_shared_folder/src/zen_shared_folder_cipher.dart';

import 'support/devices.dart';

void main() {
  late ZenSharedFolderCipher cipher;
  setUp(() async => cipher = await ZenSharedFolderCipher.derive(syncKey));

  test('a record round-trips with its name and payload', () async {
    final sealed = await cipher.seal('items:abc', [1, 2, 3], 'dev/file.zen');

    final record = await cipher.open(sealed, 'dev/file.zen');

    expect(record.name, 'items:abc');
    expect(record.payload, [1, 2, 3]);
  });

  test('the same record always gets the same file name, and another key another one', () async {
    final other = await ZenSharedFolderCipher.derive(otherSyncKey);

    expect(await cipher.fileName('items:1'), await cipher.fileName('items:1'));
    expect(await cipher.fileName('items:1'), isNot(await cipher.fileName('items:2')));
    expect(await cipher.fileName('items:1'), isNot(await other.fileName('items:1')));
    expect(await cipher.fileName('items:1'), matches(RegExp(r'^[0-9a-f]{64}\.zen$')));
  });

  test('a file opened at another path does not open', () async {
    final sealed = await cipher.seal('items:1', [9], 'dev/a.zen');

    expect(() => cipher.open(sealed, 'dev/b.zen'), throwsA(isA<ZenSharedFileException>()));
  });

  test('another key, a flipped byte and a truncation do not open', () async {
    final other = await ZenSharedFolderCipher.derive(otherSyncKey);
    final sealed = await cipher.seal('items:1', List.filled(64, 7), 'd/f.zen');
    final flipped = Uint8List.fromList(sealed)..[sealed.length ~/ 2] ^= 1;

    for (final bad in [sealed.sublist(0, sealed.length ~/ 2), flipped]) {
      expect(() => cipher.open(bad, 'd/f.zen'), throwsA(isA<ZenSharedFileException>()));
    }
    expect(() => other.open(sealed, 'd/f.zen'), throwsA(isA<ZenSharedFileException>()));
  });

  test('a file that is not ours, and one from a newer format, are told apart', () async {
    final sealed = await cipher.seal('items:1', [1], 'd/f.zen');
    final newer = Uint8List.fromList(sealed)..[3] = ZenSharedFolderCipher.format + 1;

    expect(
      () => cipher.open(Uint8List.fromList([1, 2, 3, 4, 5]), 'd/f.zen'),
      throwsA(isA<ZenSharedFileException>().having((e) => e.newerVersion, 'newerVersion', false)),
    );
    expect(
      () => cipher.open(newer, 'd/f.zen'),
      throwsA(isA<ZenSharedFileException>().having((e) => e.newerVersion, 'newerVersion', true)),
    );
  });

  test('ciphertext carries neither the name nor the payload', () async {
    final sealed = await cipher.seal('items:visible-id', 'visible-payload'.codeUnits, 'd/f.zen');
    final text = String.fromCharCodes(sealed);

    expect(text, isNot(contains('visible-id')));
    expect(text, isNot(contains('visible-payload')));
  });

  test('a key of the wrong length is refused', () {
    expect(() => ZenSharedFolderCipher.derive([1, 2, 3]), throwsArgumentError);
  });
}
