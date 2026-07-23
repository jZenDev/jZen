import 'dart:io';

import 'strategy.dart';

/// Strategy for logging in IO environments (Server/CLI).
class ZenLoggerStrategyIO implements ZenLoggerStrategy {
  @override
  void log(String message, {bool isError = false, String? origin}) {
    final out = origin != null ? '[$origin] $message' : message;
    if (isError) {
      stderr.writeln(out);
    } else {
      stdout.writeln(out);
    }
  }
}

/// Returns the IO logging strategy.
ZenLoggerStrategy getStrategy() => ZenLoggerStrategyIO();
