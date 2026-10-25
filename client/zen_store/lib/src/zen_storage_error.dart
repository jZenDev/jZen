import 'package:meta/meta.dart';
import 'package:zen_core/zen_core.dart';

/// A failure to read or write the store's files: a damaged log, a disk error, a closed store.
///
/// It is a [ZenError] of its own rather than a [ZenUnknownError] because the remedy differs: the
/// user's data is on disk and may be intact, so the application should say so and stop, not retry
/// or start empty.
@immutable
final class ZenStorageError extends ZenError {
  /// Creates a [ZenStorageError].
  const ZenStorageError(super.message, {super.internalData, super.stackTrace});
}
