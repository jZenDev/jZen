// Ported from
// ../DartZen/packages/dartzen_localization/test/zen_localization_loader_io_test.dart.
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:zen_localization/src/loader/loader_io.dart';

void main() {
  group('ZenLocalizationLoaderIO', () {
    test('loads file content', () async {
      final tempDir = await Directory.systemTemp.createTemp('zen_loc_io');
      final file = File(p.join(tempDir.path, 'test.json'));
      await file.writeAsString('{"foo": "bar"}');
      final loader = ZenLocalizationLoaderIO();
      final content = await loader.load(file.path);
      expect(content, '{"foo": "bar"}');
      await tempDir.delete(recursive: true);
    }, skip: kIsWeb);

    test('throws FileSystemException if file missing', () async {
      final loader = ZenLocalizationLoaderIO();
      expect(
        () => loader.load('/no/such/file.json'),
        throwsA(isA<FileSystemException>()),
      );
    }, skip: kIsWeb);

    test('getLoader returns ZenLocalizationLoaderIO', () {
      final loader = getLoader();
      expect(loader, isA<ZenLocalizationLoaderIO>());
    });
  });
}
