import 'package:zen_core/zen_core.dart';

import 'generated/identity_localizations.dart';

/// Maps a [ZenError] to its localized wording.
///
/// This is the one part of the retired `IdentityMessages` that was never a message: the
/// wording itself is generated from the ARB files like everything else, but *choosing* which
/// message a failure deserves is logic, and logic has no place in a generated file (STANDARDS
/// "a tracked generated file is never hand-edited" - the same reasoning applies to a built
/// one). An extension keeps it typed and on the generated class without touching it.
///
/// An error jZen does not model is shown as its own message rather than
/// [IdentityLocalizations.unknownError], preserving the behavior the string-key version had:
/// a server-supplied explanation beats a generic one.
extension IdentityErrorText on IdentityLocalizations {
  /// The localized text for [error].
  ///
  /// A transport error (a server 4xx) carries the server's stable code in [ZenError.internalData];
  /// known auth codes are mapped to localized, user-facing wording here. This is deliberate: the
  /// server sends a safe code and only a fallback message, so the UI never shows a raw upstream
  /// string (e.g. a provider name) — a matter of both UX and not leaking internals.
  String errorText(ZenError error) {
    final code = error.internalData?['code'];
    if (code is String) {
      final mapped = switch (code) {
        'invalid_credentials' => errorInvalidCredentials,
        'email_not_confirmed' => errorEmailNotConfirmed,
        'email_taken' => errorEmailTaken,
        'unauthorized' => errorUnauthorized,
        _ => null,
      };
      if (mapped != null) return mapped;
    }
    return switch (error) {
      ZenUnauthorizedError() => errorUnauthorized,
      ZenNotFoundError() => errorNotFound,
      ZenValidationError() => errorValidation,
      ZenConflictError() => errorConflict,
      _ => error.message,
    };
  }
}
