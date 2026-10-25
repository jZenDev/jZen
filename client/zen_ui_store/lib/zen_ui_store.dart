/// jZen UI Store - what a light jZen application shows when two devices changed the same data
/// differently, so that the person, not the sync, decides what to keep — and when sync stops.
///
/// - [ZenConflictBanner]: says that choices are waiting, and opens them
/// - [ZenConflictsScreen]: every record in conflict
/// - [ZenConflictResolveScreen]: each device's version of one record, and the button that keeps it
/// - [ZenSyncStatusBanner]: says why sync stopped, in words the person can act on
/// - [ZenConflictSource]: which collections to show, and how to name a record and its fields
/// - [storeLocaleDelegate]: this package's strings, for `MaterialApp.localizationsDelegates`
///
/// See docs/architecture/DECISIONS.md ADR-065.
library;

export 'src/l10n/generated/store_localizations.dart';
export 'src/l10n/store_locale_delegate.dart';
export 'src/screens/zen_conflict_resolve_screen.dart';
export 'src/screens/zen_conflicts_screen.dart';
export 'src/state/zen_conflict_source.dart' show ZenConflictSource;
export 'src/widgets/zen_conflict_banner.dart';
export 'src/widgets/zen_conflict_side_card.dart';
export 'src/widgets/zen_sync_status_banner.dart';
