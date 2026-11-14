import 'dart:io';

import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';

/// iOS Data Protection for the directory a `ZenStore` writes into. Apple-only, so it lives with
/// the other Apple half of a Local application and not with the store key, which every platform has.
abstract final class ZenDataProtection {
  static const MethodChannel _channel = MethodChannel('zen_store_cloudkit');

  /// Gives [directory] iOS Data Protection `complete`: unreadable while the device is locked, and
  /// inherited by every file the store writes there. Call it before `ZenStore.open`. Succeeds with
  /// false on macOS, which has no such class -- the store's own encryption protects it there --
  /// and on any platform without this plugin.
  static Future<ZenResult<bool>> protectDirectory(Directory directory) async {
    try {
      final protected = await _channel.invokeMethod<bool>('protectDirectory', {
        'path': directory.path,
      });
      return ZenResult.ok(protected ?? false);
    } on MissingPluginException {
      return const ZenResult.ok(false);
    } on PlatformException catch (e, stack) {
      return ZenResult.err(
        ZenUnknownError(
          'Data Protection could not be set on ${directory.path}: ${e.message}',
          stackTrace: stack,
        ),
      );
    }
  }
}
