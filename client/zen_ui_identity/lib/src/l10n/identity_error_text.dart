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
  String errorText(ZenError error) => switch (error) {
    ZenUnauthorizedError() => errorUnauthorized,
    ZenNotFoundError() => errorNotFound,
    ZenValidationError() => errorValidation,
    ZenConflictError() => errorConflict,
    _ => error.message,
  };
}
