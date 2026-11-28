/// jZen UI Store - what a jZen Local application shows when two devices changed the same data
/// differently, so that the person, not the sync, decides what to keep — and when sync stops.
///
/// - [ZenConflictBanner]: says that choices are waiting, and opens them
/// - [ZenConflictsScreen]: every record in conflict
/// - [ZenConflictResolveScreen]: every version of one record, each with the button that keeps it
/// - [ZenConflictBulkScreen]: one choice that settles every record two devices disagree on
/// - [ZenIssueSource]: the application's own cross-record problems, listed beside the conflicts
/// - [ZenIssueScreen]: one such problem, with the application's actions as buttons
/// - [ZenSyncStatusBanner]: says why sync stopped, in words the person can act on
/// - [ZenConflictSource]: which collections to show, and how to name a record and its fields
/// - [ZenAddDeviceScreen]: shows the code a new device joins with, and when it expires
/// - [ZenJoinScreen]: where a new device scans or types that code
/// - [storeLocaleDelegate]: this package's strings, for `MaterialApp.localizationsDelegates`
///
/// See docs/architecture/DECISIONS.md ADR-065.
library;

export 'src/l10n/generated/store_localizations.dart';
export 'src/l10n/store_locale_delegate.dart';
export 'src/screens/zen_add_device_screen.dart';
export 'src/screens/zen_conflict_bulk_screen.dart' show ZenConflictBulkScreen;
export 'src/screens/zen_conflict_resolve_screen.dart';
export 'src/screens/zen_conflicts_screen.dart';
export 'src/screens/zen_issue_screen.dart';
export 'src/screens/zen_join_screen.dart' show ZenJoinScreen, ZenQrScannerBuilder;
export 'src/state/zen_conflict_source.dart' show ZenConflictSource;
export 'src/state/zen_issue_source.dart'
    show
        ZenChoiceIssueAction,
        ZenIssue,
        ZenIssueAction,
        ZenIssueSource,
        ZenPlainIssueAction,
        ZenTextIssueAction;
export 'src/widgets/zen_conflict_banner.dart';
export 'src/widgets/zen_conflict_side_card.dart';
export 'src/widgets/zen_pairing_code_view.dart';
export 'src/widgets/zen_sync_status_banner.dart';
