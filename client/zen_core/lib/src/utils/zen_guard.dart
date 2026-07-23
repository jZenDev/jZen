import '../result/zen_error.dart';
import '../result/zen_result.dart';

/// A set of validation guards that return [ZenResult] instead of throwing exceptions.
///
/// Use these to validate conditions early in your logic flow.
class ZenGuard {
  const ZenGuard._();

  /// Ensures that [condition] is true.
  ///
  /// Returns [ZenSuccess] with true if valid.
  /// Returns [ZenFailure] with [ZenValidationError] if invalid.
  static ZenResult<bool> ensure(bool condition, String message) {
    if (!condition) {
      return ZenResult.err(ZenValidationError(message));
    }
    return const ZenResult.ok(true);
  }

  /// Ensures that [value] is not null.
  static ZenResult<T> notNull<T>(T? value, String name) {
    if (value == null) {
      return ZenResult.err(ZenValidationError('$name cannot be null'));
    }
    return ZenResult.ok(value);
  }

  /// Ensures that string [value] is not empty.
  static ZenResult<String> notEmpty(String value, String name) {
    if (value.isEmpty) {
      return ZenResult.err(ZenValidationError('$name cannot be empty'));
    }
    return ZenResult.ok(value);
  }
}
