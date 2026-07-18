// Ported verbatim from
// ../DartZen/packages/dartzen_localization/lib/src/loader/loader_flutter.dart.
// This is the ONLY file that imports package:flutter; it is compiled in only when
// `dart.library.ui` is present (TA-3, docs/architecture/BLUEPRINT.md).
import 'dart:async';

// TA-3: `flutter` is intentionally a dev-only dependency so Dart-only consumers do not pull
// in the Flutter SDK. This file is compiled in only when `dart.library.ui` is present, at
// which point a Flutter consumer supplies `flutter`. See docs/architecture/BLUEPRINT.md.
// ignore: depend_on_referenced_packages
import 'package:flutter/services.dart';

import 'loader_stub.dart';

/// Loads assets on Flutter (Mobile, Web, Desktop).
class ZenLocalizationLoaderFlutter implements ZenLocalizationLoaderImpl {
  @override
  Future<String> load(String path) async {
    // Flutter assets are typically loaded via rootBundle.
    // The path here is assumed to be an asset key.
    try {
      return await rootBundle.loadString(path);
    } catch (e) {
      // Map Flutter asset error to something generic or rethrow?
      // Service will catch it.
      rethrow;
    }
  }
}

/// Returns the correct loader implementation.
ZenLocalizationLoaderImpl getLoader() => ZenLocalizationLoaderFlutter();
