// Ported from
// ../DartZen/packages/dartzen_core/lib/src/logging/impl/strategy_flutter.dart.
// The donor's default log name 'dartzen.core.ZenLogger' is renamed 'zen.core.ZenLogger'.
import 'dart:developer' as developer;

import 'strategy.dart';

/// Strategy for logging in Flutter environments.
class ZenLoggerStrategyFlutter implements ZenLoggerStrategy {
  @override
  void log(String message, {bool isError = false, String? origin}) {
    // Use `dart:developer` to write logs in Flutter/web environments.
    final name = origin ?? 'zen.core.ZenLogger';
    developer.log(message, level: isError ? 1000 : 800, name: name);
  }
}

/// Returns the Flutter logging strategy.
ZenLoggerStrategy getStrategy() => ZenLoggerStrategyFlutter();
