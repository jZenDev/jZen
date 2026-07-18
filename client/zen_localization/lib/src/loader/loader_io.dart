// Ported verbatim from
// ../DartZen/packages/dartzen_localization/lib/src/loader/loader_io.dart.
import 'dart:async';
import 'dart:io';

import 'loader_stub.dart';

/// Loads files from the local filesystem (Server/CLI).
class ZenLocalizationLoaderIO implements ZenLocalizationLoaderImpl {
  @override
  Future<String> load(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File not found', path);
    }
    return file.readAsString();
  }
}

/// Returns the correct loader implementation.
ZenLocalizationLoaderImpl getLoader() => ZenLocalizationLoaderIO();
