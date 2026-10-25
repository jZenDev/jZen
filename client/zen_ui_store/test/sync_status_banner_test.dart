import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import 'support/conflict_fixture.dart';

final class _Transport implements ZenSyncTransport {
  // Synchronous, so each `set` reaches the banner before the next pump: an async broadcast
  // controller delivers on a microtask that may land after that pump's frame.
  final StreamController<ZenSyncStatus> controller = StreamController.broadcast(sync: true);
  @override
  ZenSyncStatus status = const ZenSyncStatus(ZenSyncState.upToDate);

  void set(ZenSyncStatus next) {
    status = next;
    controller.add(next);
  }

  @override
  Stream<ZenSyncStatus> get statusChanges => controller.stream;
  @override
  Future<void> syncNow() async {}
  @override
  Future<void> stop() async {}
}

void main() {
  testWidgets('says nothing while sync works, and why when it stops', (tester) async {
    final transport = _Transport();
    await tester.pumpWidget(
      conflictApp(
        home: Scaffold(body: ZenSyncStatusBanner(transport: transport)),
      ),
    );
    expect(
      find.descendant(of: find.byType(ZenSyncStatusBanner), matching: find.byType(Text)),
      findsNothing,
    );

    transport.set(
      const ZenSyncStatus(ZenSyncState.unavailable, issue: ZenSyncIssue.accountChanged),
    );
    await tester.pump();
    expect(find.textContaining('different iCloud account'), findsOneWidget);

    transport.set(const ZenSyncStatus(ZenSyncState.syncing));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(ZenSyncStatusBanner), matching: find.byType(Text)),
      findsNothing,
    );
  });

  for (final issue in [...ZenSyncIssue.values, null]) {
    testWidgets('every issue has words of its own, legible (${issue?.name ?? 'none'})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final transport = _Transport()
        ..status = ZenSyncStatus(ZenSyncState.unavailable, issue: issue);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          conflictApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
            ),
            home: Scaffold(body: ZenSyncStatusBanner(transport: transport)),
          ),
        );
        expect(
          find.descendant(of: find.byType(ZenSyncStatusBanner), matching: find.byType(Text)),
          findsOneWidget,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
      handle.dispose();
    });
  }
}
