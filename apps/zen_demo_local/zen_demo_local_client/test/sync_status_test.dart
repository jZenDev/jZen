import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import 'package:zen_demo_local_client/src/demo_local_app.dart';

import 'support/bare_session.dart';

/// `ZenSyncStatusBanner` for every status a transport can report, in both languages: the person
/// who is not syncing is told why, and nothing is shown while sync works.
void main() {
  // Each issue and the words the banner owes the person for it.
  final issues = <ZenSyncIssue, String Function(StoreLocalizations)>{
    ZenSyncIssue.noAccount: (m) => m.syncNoAccount,
    ZenSyncIssue.keychainUnavailable: (m) => m.syncKeychainUnavailable,
    ZenSyncIssue.accountChanged: (m) => m.syncAccountChanged,
    ZenSyncIssue.cloudDataDeleted: (m) => m.syncCloudDataDeleted,
    ZenSyncIssue.quotaExceeded: (m) => m.syncQuotaExceeded,
    ZenSyncIssue.unreadableRecords: (m) => m.syncUnreadableRecords,
    ZenSyncIssue.noFolder: (m) => m.syncNoFolder,
    ZenSyncIssue.folderUnreachable: (m) => m.syncFolderUnreachable,
    ZenSyncIssue.accessRevoked: (m) => m.syncAccessRevoked,
    ZenSyncIssue.notPaired: (m) => m.syncNotPaired,
    ZenSyncIssue.newerAppVersion: (m) => m.syncNewerAppVersion,
    ZenSyncIssue.other: (m) => m.syncOther,
  };

  for (final tag in const ['en', 'uk']) {
    testWidgets('every sync status is shown in words, or not at all ($tag)', (tester) async {
      tester.platformDispatcher.localesTestValue = [Locale(tag)];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final transport = FakeTransport();
      final session = await openBareSession(tester, transport: transport);
      final lock = (await ZenPinLock.load(
        storage: ZenMemoryLockStorage(),
        iterations: 1,
      )).dataOrNull!;
      final messages = lookupStoreLocalizations(Locale(tag));
      await tester.pumpWidget(DemoLocalApp(session: session, lock: lock));
      await tester.pumpAndSettle();

      // Working: nothing is shown.
      for (final state in [ZenSyncState.upToDate, ZenSyncState.syncing]) {
        transport.emit(ZenSyncStatus(state));
        await tester.pump();
        expect(find.byType(ZenSyncStatusBanner, skipOffstage: false), findsOneWidget);
        for (final say in issues.values) {
          expect(
            find.text(say(messages), skipOffstage: false),
            findsNothing,
            reason: '${state.name} must say nothing',
          );
        }
      }

      // Stopped: each issue says its own words, and only those.
      for (final entry in issues.entries) {
        transport.emit(ZenSyncStatus(ZenSyncState.unavailable, issue: entry.key));
        await tester.pump();
        expect(
          find.text(entry.value(messages), skipOffstage: false),
          findsOneWidget,
          reason: entry.key.name,
        );
      }
    });
  }

  testWidgets('a build whose transport is refused says why instead of showing nothing', (
    tester,
  ) async {
    final session = await openBareSession(tester, refusal: 'ZEN_PLATFORM is web.');
    final lock = (await ZenPinLock.load(
      storage: ZenMemoryLockStorage(),
      iterations: 1,
    )).dataOrNull!;
    await tester.pumpWidget(DemoLocalApp(session: session, lock: lock));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Sync is not available in this build: ZEN_PLATFORM is web.'),
      findsOneWidget,
    );
  });
}
