// Ported verbatim from
// ../DartZen/packages/dartzen_core/lib/src/value_objects/common_types.dart.
import 'package:meta/meta.dart';

import '../result/zen_error.dart';
import '../result/zen_result.dart';

/// A wrapper for a validated UTC DateTime.
///
/// Ensures strict adherence to UTC and provides immutability.
@immutable
final class ZenTimestamp {
  /// The underlying UTC DateTime.
  final DateTime value;

  const ZenTimestamp._(this.value);

  /// Creates a [ZenTimestamp] from the current time in UTC.
  factory ZenTimestamp.now() => ZenTimestamp._(DateTime.now().toUtc());

  /// Creates a [ZenTimestamp] from a specific [dateTime].
  ///
  /// Forces the [dateTime] to UTC.
  factory ZenTimestamp.from(DateTime dateTime) =>
      ZenTimestamp._(dateTime.toUtc());

  @override
  String toString() => value.toIso8601String();

  @override
  bool operator ==(Object other) =>
      other is ZenTimestamp && other.value == value;

  @override
  int get hashCode => value.hashCode;

  /// Returns true if this timestamp is before [other].
  bool isBefore(ZenTimestamp other) => value.isBefore(other.value);

  /// Returns true if this timestamp is after [other].
  bool isAfter(ZenTimestamp other) => value.isAfter(other.value);

  /// Returns the number of milliseconds since epoch.
  int get millisecondsSinceEpoch => value.millisecondsSinceEpoch;

  /// Creates a [ZenTimestamp] from [milliseconds] since epoch.
  factory ZenTimestamp.fromMilliseconds(int milliseconds) => ZenTimestamp._(
    DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
  );
}

/// A value object representing a locale with a mandatory language code
/// and an optional region code.
///
/// Compliant with ISO 639-1 (language) and ISO 3166-1 (region).
@immutable
final class ZenLocale {
  /// The ISO 639-1 language code (e.g., "en", "uk").
  final String languageCode;

  /// The optional ISO 3166-1 region code (e.g., "UA").
  final String? regionCode;

  const ZenLocale._(this.languageCode, this.regionCode);

  /// Creates and validates a [ZenLocale].
  ///
  /// [languageCode] must be 2 lowercase letters.
  /// [regionCode] if present must be 2 uppercase letters.
  static ZenResult<ZenLocale> create({
    required String languageCode,
    String? regionCode,
  }) {
    if (!RegExp(r'^[a-z]{2}$').hasMatch(languageCode)) {
      return ZenResult.err(
        ZenValidationError('Invalid language code: $languageCode'),
      );
    }

    if (regionCode != null && !RegExp(r'^[A-Z]{2}$').hasMatch(regionCode)) {
      return ZenResult.err(
        ZenValidationError('Invalid region code: $regionCode'),
      );
    }

    return ZenResult.ok(ZenLocale._(languageCode, regionCode));
  }

  /// Returns the string representation (e.g., "uk" or "uk_UA").
  @override
  String toString() =>
      regionCode == null ? languageCode : '${languageCode}_$regionCode';

  @override
  bool operator ==(Object other) =>
      other is ZenLocale &&
      other.languageCode == languageCode &&
      other.regionCode == regionCode;

  @override
  int get hashCode => Object.hash(languageCode, regionCode);
}
