/// jZen Core - Universal result types, value objects, and shared contracts.
///
/// This package provides the foundational building blocks for the jZen ecosystem:
/// - Result types (ZenResult, ZenSuccess, ZenFailure)
/// - Error hierarchy (ZenError and subtypes)
/// - Value objects (ZenTimestamp, ZenLocale, EmailAddress, UserId)
/// - Base response contract (BaseResponse)
/// - The supported locale set (ZenLocales), mirroring the server's zen.core.i18n.ZenLocales
///
/// Ported from ../DartZen/packages/dartzen_core/lib/dartzen_core.dart.
library;

export 'src/i18n/zen_locales.dart';
export 'src/logging/zen_logger.dart';
export 'src/response/base_response.dart';
export 'src/result/zen_error.dart';
export 'src/result/zen_result.dart';
export 'src/utils/zen_guard.dart';
export 'src/utils/zen_try.dart';
export 'src/value_objects/common_types.dart';
export 'src/value_objects/ids.dart';
export 'src/zen_constants.dart';
