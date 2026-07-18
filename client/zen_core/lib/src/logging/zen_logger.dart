// Ported from ../DartZen/packages/dartzen_core/lib/src/logging/zen_logger.dart.
// The conditional import is preserved verbatim: it tree-shakes the platform-specific
// strategy so only one is compiled in (stub / dart:io / Flutter dart:developer).
import 'impl/strategy_stub.dart'
    if (dart.library.io) 'impl/strategy_io.dart'
    if (dart.library.ui) 'impl/strategy_flutter.dart';

/// Minimal logging abstraction for jZen.
///
/// Use [ZenLogger.instance] to log messages.
/// Do NOT instantiate your own logger in feature packages.
abstract class ZenLogger {
  /// The shared logger instance.
  static ZenLogger instance = _DefaultZenLogger();

  /// Logs a debug message (dev diagnostics).
  void debug(String message, {Map<String, dynamic>? internalData});

  /// Logs an info message (general events).
  void info(String message, {Map<String, dynamic>? internalData});

  /// Logs a warning message (potential issues).
  void warn(String message, {Map<String, dynamic>? internalData});

  /// Logs an error message (failures).
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? internalData,
  });
}

/// Default implementation using configured strategy (IO vs Flutter).
class _DefaultZenLogger implements ZenLogger {
  final _strategy = getStrategy();

  @override
  void debug(String message, {Map<String, dynamic>? internalData}) {
    _log('[DEBUG] $message', internalData: internalData);
  }

  @override
  void info(String message, {Map<String, dynamic>? internalData}) {
    _log('[INFO] $message', internalData: internalData);
  }

  @override
  void warn(String message, {Map<String, dynamic>? internalData}) {
    _log('[WARN] $message', internalData: internalData);
  }

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? internalData,
  }) {
    final sb = StringBuffer('[ERROR] $message');
    if (error != null) sb.write('\n$error');
    if (stackTrace != null) sb.write('\n$stackTrace');
    _log(sb.toString(), isError: true, internalData: internalData);
  }

  void _log(
    String line, {
    bool isError = false,
    Map<String, dynamic>? internalData,
  }) {
    // For now, we just append the data to the line if present
    final finalMessage = internalData != null
        ? '$line\nData: $internalData'
        : line;
    _strategy.log(finalMessage, isError: isError);
  }
}
