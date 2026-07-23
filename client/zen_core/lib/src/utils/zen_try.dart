import 'dart:async';

import '../result/zen_error.dart';
import '../result/zen_result.dart';

/// A functional utility for safely executing code that might throw exceptions.
class ZenTry {
  const ZenTry._();

  /// Executes the [block] and returns a [ZenResult].
  ///
  /// If [block] returns normally, wraps the result in [ZenSuccess].
  /// If [block] throws an exception, catches it and wraps it in [ZenFailure].
  static ZenResult<T> call<T>(T Function() block) {
    try {
      return ZenResult.ok(block());
    } catch (e, stack) {
      return ZenResult.err(ZenUnknownError(e.toString(), stackTrace: stack));
    }
  }

  /// Executes the asynchronous [block] and returns a `Future<ZenResult>`.
  ///
  /// Handles exceptions asynchronously.
  static Future<ZenResult<T>> callAsync<T>(Future<T> Function() block) async {
    try {
      final result = await block();
      return ZenResult.ok(result);
    } catch (e, stack) {
      return ZenResult.err(ZenUnknownError(e.toString(), stackTrace: stack));
    }
  }
}
