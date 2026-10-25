import 'package:zen_core/zen_core.dart';

import '../state/zen_pin_locked_out_error.dart';
import 'generated/lock_localizations.dart';

/// What to tell the person for an error from `ZenPinLock`.
String lockErrorText(LockLocalizations messages, ZenError error) => switch (error) {
  ZenPinLockedOutError(:final retryAfter) => messages.lockedOut(
    (retryAfter.inMilliseconds / 1000).ceil(),
  ),
  ZenUnauthorizedError() => messages.wrongPin,
  ZenValidationError() => messages.pinFormat,
  _ => messages.lockError,
};
