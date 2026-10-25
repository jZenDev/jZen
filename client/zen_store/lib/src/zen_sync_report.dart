import 'package:meta/meta.dart';

/// What merging one batch of incoming records did.
@immutable
final class ZenSyncReport {
  /// The collections whose contents or conflicts changed.
  final Set<String> changed;

  /// How many records now wait for a person to resolve a conflict, across the whole store. Not
  /// zero means the application must say so — `zen_ui_store`'s `ZenConflictBanner` does.
  final int conflicts;

  /// The records that could not be read. Each is skipped and the rest are merged, because one
  /// unreadable record — from a newer app version, or damaged — must not stop the others.
  final List<ZenSyncProblem> problems;

  /// Creates a report.
  const ZenSyncReport({required this.changed, required this.conflicts, required this.problems});

  @override
  String toString() =>
      'ZenSyncReport(changed: $changed, conflicts: $conflicts, problems: $problems)';
}

/// A record a sync could not read, and why.
@immutable
final class ZenSyncProblem {
  /// The record's name.
  final String record;

  /// Why it was skipped.
  final String message;

  /// Creates a problem.
  const ZenSyncProblem(this.record, this.message);

  @override
  String toString() => '$record: $message';
}
