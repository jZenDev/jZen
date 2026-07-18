// Ported verbatim from
// ../DartZen/packages/dartzen_core/lib/src/response/base_response.dart.
import 'package:meta/meta.dart';

import '../result/zen_error.dart';

/// Canonical error codes for [BaseResponse]. Centralized here so no code string is
/// hand-written at the call sites; each maps to its stable wire value via [wire].
enum BaseResponseErrorCode {
  /// An unexpected or unclassified failure.
  unknown('UNKNOWN_ERROR'),

  /// Invalid input or malformed data.
  validation('VALIDATION_ERROR'),

  /// A requested resource could not be found.
  notFound('NOT_FOUND_ERROR'),

  /// An authentication or authorization failure.
  unauthorized('UNAUTHORIZED_ERROR'),

  /// A conflict such as a duplicate record.
  conflict('CONFLICT_ERROR');

  const BaseResponseErrorCode(this.wire);

  /// The stable string value carried on the wire.
  final String wire;
}

/// A universal response contract for jZen services.
///
/// This structure is used across boundaries (e.g. Server -> Client).
@immutable
final class BaseResponse<T> {
  /// Whether the operation completed successfully.
  final bool success;

  /// A descriptive message for the user or logs.
  final String message;

  /// The payload data, if any.
  final T? data;

  /// A code identifying the error type, if any.
  final String? errorCode;

  /// The UTC timestamp when the response was created.
  final DateTime timestamp;

  const BaseResponse._({
    required this.success,
    required this.message,
    required this.timestamp,
    this.data,
    this.errorCode,
  });

  /// Creates a successful response.
  factory BaseResponse.success(T data, {String message = 'Success'}) =>
      BaseResponse._(
        success: true,
        message: message,
        data: data,
        timestamp: DateTime.now().toUtc(),
      );

  /// Creates a failure response.
  factory BaseResponse.failure(String message, {String? errorCode, T? data}) =>
      BaseResponse._(
        success: false,
        message: message,
        errorCode: errorCode ?? BaseResponseErrorCode.unknown.wire,
        data: data,
        timestamp: DateTime.now().toUtc(),
      );

  /// Creates a failure response from a [ZenError].
  factory BaseResponse.fromError(ZenError error, {T? data}) {
    // Map each ZenError subtype to its canonical error code.
    final code = switch (error) {
      ZenValidationError() => BaseResponseErrorCode.validation,
      ZenNotFoundError() => BaseResponseErrorCode.notFound,
      ZenUnauthorizedError() => BaseResponseErrorCode.unauthorized,
      ZenConflictError() => BaseResponseErrorCode.conflict,
      _ => BaseResponseErrorCode.unknown,
    };

    return BaseResponse._(
      success: false,
      message: error.message,
      errorCode: code.wire,
      data: data,
      timestamp: DateTime.now().toUtc(),
    );
  }

  @override
  String toString() =>
      'BaseResponse(success: $success, message: "$message", data: $data, errorCode: $errorCode, timestamp: $timestamp)';
}
