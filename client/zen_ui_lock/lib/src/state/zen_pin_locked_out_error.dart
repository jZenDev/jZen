import 'package:meta/meta.dart';
import 'package:zen_core/zen_core.dart';

/// Too many wrong PINs: no attempt is checked until [retryAfter] has passed.
@immutable
final class ZenPinLockedOutError extends ZenError {
  /// How long until the next attempt is accepted.
  final Duration retryAfter;

  /// Creates a [ZenPinLockedOutError].
  const ZenPinLockedOutError(this.retryAfter)
    : super('Too many wrong PINs; the next attempt is accepted after a wait.');
}
