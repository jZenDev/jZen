import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zen_save_file/zen_save_file.dart';

/// A platform that saves into a directory, the way a save sheet does, or cancels, or refuses.
final class _FakePlatform implements ZenSaveFilePort {
  final Directory target;
  bool cancel = false;
  bool refuse = false;
  String? mimeType;

  _FakePlatform(this.target);

  @override
  Future<bool> save(String name, Uint8List bytes, String mimeType) async {
    this.mimeType = mimeType;
    if (cancel) return false;
    if (refuse) throw const FileSystemException('no space left on device');
    await File('${target.path}/$name').writeAsBytes(bytes);
    return true;
  }
}

void main() {
  late Directory target;
  late _FakePlatform platform;

  setUp(() async {
    target = await Directory.systemTemp.createTemp('zen_save_file_test');
    platform = _FakePlatform(target);
  });
  tearDown(() => target.delete(recursive: true));

  final bytes = Uint8List.fromList([1, 2, 3, 250, 0, 7]);

  test('a known byte string is saved under the given name and reads back', () async {
    final saved = await zenSaveFile(
      'export.json',
      bytes,
      mimeType: 'application/json',
      port: platform,
    );

    expect(saved, isTrue);
    expect(await File('${target.path}/export.json').readAsBytes(), bytes);
    expect(platform.mimeType, 'application/json');
  });

  test('a cancel returns false and writes nothing', () async {
    platform.cancel = true;

    final saved = await zenSaveFile('export.json', bytes, port: platform);

    expect(saved, isFalse);
    expect(target.listSync(), isEmpty);
  });

  test('a refused write throws, and is not a cancel', () async {
    platform.refuse = true;

    await expectLater(
      zenSaveFile('export.json', bytes, port: platform),
      throwsA(isA<ZenSaveFileError>().having((e) => e.message, 'message', contains('no space'))),
    );
    expect(target.listSync(), isEmpty);
  });

  test(
    'a name with a folder in it, or an empty one, is refused before the platform is asked',
    () async {
      for (final name in ['', '  ', 'a/b.json', r'a\b.json']) {
        await expectLater(
          zenSaveFile(name, bytes, port: platform),
          throwsA(isA<ZenSaveFileError>()),
        );
      }
      expect(platform.mimeType, isNull);
    },
  );
}
