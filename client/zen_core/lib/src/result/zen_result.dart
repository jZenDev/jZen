import 'package:meta/meta.dart';

import 'zen_error.dart';

/// A functional Result type representing either a success or a failure.
///
/// [ZenResult] is a sealed union of [ZenSuccess] and [ZenFailure].
/// It forces consumers to handle both cases or use helper methods to transformation.
///
/// Usage:
/// ```dart
/// ZenResult<int> divide(int a, int b) {
///   if (b == 0) return ZenResult.err(ZenValidationError('Division by zero'));
///   return ZenResult.ok(a ~/ b);
/// }
/// ```
@immutable
sealed class ZenResult<T> {
  const ZenResult._();

  /// Creates a successful result containing [data].
  const factory ZenResult.ok(T data) = ZenSuccess<T>;

  /// Creates a failed result containing a [ZenError].
  const factory ZenResult.err(ZenError error) = ZenFailure<T>;

  /// Returns `true` if this result is a [ZenSuccess].
  bool get isSuccess;

  /// Returns `true` if this result is a [ZenFailure].
  bool get isFailure;

  /// Returns the data if this is a [ZenSuccess], otherwise returns `null`.
  T? get dataOrNull;

  /// Returns the error if this is a [ZenFailure], otherwise returns `null`.
  ZenError? get errorOrNull;

  /// Folds the result into a single value by applying [onSuccess] if successful,
  /// or [onFailure] if failed.
  R fold<R>(R Function(T data) onSuccess, R Function(ZenError error) onFailure);
}

/// Represents a successful operation containing a value of type [T].
@immutable
final class ZenSuccess<T> extends ZenResult<T> {
  /// The successful value.
  final T data;

  /// Creates a [ZenSuccess] wrapper.
  const ZenSuccess(this.data) : super._();

  @override
  bool get isSuccess => true;

  @override
  bool get isFailure => false;

  @override
  T? get dataOrNull => data;

  @override
  ZenError? get errorOrNull => null;

  @override
  R fold<R>(
    R Function(T data) onSuccess,
    R Function(ZenError error) onFailure,
  ) => onSuccess(data);

  @override
  String toString() => 'ZenSuccess($data)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZenSuccess<T> && other.data == data;
  }

  @override
  int get hashCode => data.hashCode;
}

/// Represents a failed operation containing a [ZenError].
@immutable
final class ZenFailure<T> extends ZenResult<T> {
  /// The error describing the failure.
  final ZenError error;

  /// Creates a [ZenFailure] wrapper.
  const ZenFailure(this.error) : super._();

  @override
  bool get isSuccess => false;

  @override
  bool get isFailure => true;

  @override
  T? get dataOrNull => null;

  @override
  ZenError? get errorOrNull => error;

  @override
  R fold<R>(
    R Function(T data) onSuccess,
    R Function(ZenError error) onFailure,
  ) => onFailure(error);

  @override
  String toString() => 'ZenFailure($error)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZenFailure<T> && other.error == error;
  }

  @override
  int get hashCode => error.hashCode;
}
