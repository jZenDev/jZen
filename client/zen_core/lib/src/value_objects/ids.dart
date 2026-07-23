// Email validation delegates to the standard `email_validator` library rather than a
// hand-rolled regex (MANIFESTO: "no custom magic"; a standard, inspectable validator beats
// a maintained-by-hand regex).
import 'package:email_validator/email_validator.dart';
import 'package:meta/meta.dart';

import '../result/zen_error.dart';
import '../result/zen_result.dart';

/// A validated email address value object.
@immutable
final class EmailAddress {
  /// The raw email string.
  final String value;

  const EmailAddress._(this.value);

  /// Creates and validates an [EmailAddress].
  ///
  /// Uses a strict regex to ensure format validity.
  static ZenResult<EmailAddress> create(String rawValue) {
    if (rawValue.isEmpty) {
      return const ZenResult.err(ZenValidationError('Email cannot be empty'));
    }

    if (!EmailValidator.validate(rawValue)) {
      return const ZenResult.err(ZenValidationError('Invalid email format'));
    }

    return ZenResult.ok(EmailAddress._(rawValue));
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is EmailAddress && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A validated user identifier.
///
/// Wraps a string ID and ensures it is not empty.
@immutable
final class UserId {
  /// The string representation of the ID.
  final String value;

  const UserId._(this.value);

  /// Creates and validates a [UserId].
  static ZenResult<UserId> create(String value) {
    if (value.trim().isEmpty) {
      return const ZenResult.err(ZenValidationError('UserId cannot be empty'));
    }
    return ZenResult.ok(UserId._(value));
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is UserId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
