import 'dart:io';

import 'package:meta/meta.dart';

import 'strategy.dart';

/// Strategy for logging in IO environments (Server/CLI).
class ZenLoggerStrategyIO implements ZenLoggerStrategy {
  @override
  void log(String message, {bool isError = false, String? origin}) {
    final out = formatLine(message, origin: origin);
    if (isError) {
      stderr.writeln(out);
    } else {
      stdout.writeln(out);
    }
  }

  /// Prefixes [message] with `[origin]` when [origin] is given, unchanged
  /// otherwise. Exposed for testing since [log] writes to the real
  /// stdout/stderr and can't be asserted on directly.
  @visibleForTesting
  static String formatLine(String message, {String? origin}) =>
      origin != null ? '[$origin] $message' : message;
}

/// Returns the IO logging strategy.
ZenLoggerStrategy getStrategy() => ZenLoggerStrategyIO();
