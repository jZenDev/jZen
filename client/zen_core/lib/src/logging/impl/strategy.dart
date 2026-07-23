/// Internal strategy for logging.
abstract class ZenLoggerStrategy {
  /// Logs a [message]. [isError] indicates if it's an error level log.
  /// [origin] is an optional identifier (e.g. `MyClass.myMethod`) to help
  /// attribute logs to a specific caller or module.
  void log(String message, {bool isError = false, String? origin});
}
