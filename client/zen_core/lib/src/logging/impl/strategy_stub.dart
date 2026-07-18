// Ported verbatim from
// ../DartZen/packages/dartzen_core/lib/src/logging/impl/strategy_stub.dart.
import 'strategy.dart';

/// Fallback strategy for basic logging.
class ZenLoggerStrategyStub implements ZenLoggerStrategy {
  @override
  void log(String message, {bool isError = false, String? origin}) {
    final out = origin != null ? '[$origin] $message' : message;
    // Why print: this is the stub selected only when neither dart:io (stdout/stderr) nor
    // Flutter's dart:developer is available - i.e. no other logging sink exists on this
    // platform. `print` is the sole remaining fallback, so avoid_print is intentionally
    // suppressed on just this line.
    // ignore: avoid_print
    print(out);
  }
}

/// Returns the Stub logging strategy.
ZenLoggerStrategy getStrategy() => ZenLoggerStrategyStub();
