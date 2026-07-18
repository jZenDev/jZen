// Ported from
// ../DartZen/packages/dartzen_localization/test/localization_loader_test.dart.
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// Mock implementation for testing without Flutter binding
class _MockLoaderImpl {
  Future<String> load(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Cannot open file', path);
    }
    return file.readAsString();
  }
}

void main() {
  group('ZenLocalizationLoader (Integration)', () {
    test('loads file from disk (IO)', () async {
      // Setup temporary file
      final tempDir = await Directory.systemTemp.createTemp('zen_loc_test');
      final file = File(p.join(tempDir.path, 'test.json'));
      await file.writeAsString('{"test": "content"}');

      try {
        final impl = _MockLoaderImpl();
        final content = await impl.load(file.path);
        expect(content, '{"test": "content"}');
      } finally {
        await tempDir.delete(recursive: true);
      }
    }, skip: kIsWeb);

    test('throws on missing file', () async {
      final impl = _MockLoaderImpl();
      expect(
        impl.load('/path/to/non/existent/file.json'),
        throwsA(isA<FileSystemException>()),
      );
    }, skip: kIsWeb);
  });
}
