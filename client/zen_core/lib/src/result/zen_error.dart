import 'package:meta/meta.dart';

import 'zen_result.dart' show ZenFailure;

/// The base class for all functional errors in the Zen architecture.
///
/// [ZenError] is intended to be used as the value of a [ZenFailure], representing
/// a known, handled failure case rather than an unchecked exception.
///
/// All errors include a human-readable [message] and optional debugging details.
@immutable
abstract class ZenError {
  /// A human-readable message describing the error.
  final String message;

  /// Optional contextual data useful for debugging or logging.
  final Map<String, dynamic>? internalData;

  /// Optional stack trace captured at the point of error creation.
  final StackTrace? stackTrace;

  /// Creates a [ZenError] with a [message] and optional metadata.
  const ZenError(this.message, {this.internalData, this.stackTrace});

  @override
  String toString() => '$runtimeType: $message';
}

/// Represents a validation failure, such as invalid user input or malformed data.
@immutable
final class ZenValidationError extends ZenError {
  /// Creates a [ZenValidationError].
  const ZenValidationError(
    super.message, {
    super.internalData,
    super.stackTrace,
  });
}

/// Represents a failure where a requested resource could not be found.
@immutable
final class ZenNotFoundError extends ZenError {
  /// Creates a [ZenNotFoundError].
  const ZenNotFoundError(super.message, {super.internalData, super.stackTrace});
}

/// Represents an authentication or authorization failure.
@immutable
final class ZenUnauthorizedError extends ZenError {
  /// Creates a [ZenUnauthorizedError].
  const ZenUnauthorizedError(
    super.message, {
    super.internalData,
    super.stackTrace,
  });
}

/// Represents a conflict state, such as trying to create a duplicate record.
@immutable
final class ZenConflictError extends ZenError {
  /// Creates a [ZenConflictError].
  const ZenConflictError(super.message, {super.internalData, super.stackTrace});
}

/// Represents an unexpected or unclassified failure.
///
/// Use this for wrapping external exceptions or when the error type is unknown.
@immutable
final class ZenUnknownError extends ZenError {
  /// Creates a [ZenUnknownError].
  const ZenUnknownError(super.message, {super.internalData, super.stackTrace});
}
