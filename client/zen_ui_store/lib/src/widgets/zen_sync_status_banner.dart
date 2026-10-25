import 'package:flutter/material.dart';
import 'package:zen_store/zen_store.dart';

import '../l10n/generated/store_localizations.dart';

/// Says, for as long as it is true, that sync has stopped and why — in words the person can act
/// on (sign in, turn on iCloud Keychain, free storage, update the app). It takes no space while
/// sync works.
///
/// A sync that stops quietly is a failure swallowed: the person keeps working believing their
/// other devices see it. Put it beside `ZenConflictBanner`, where it is seen on every launch.
class ZenSyncStatusBanner extends StatelessWidget {
  /// The transport whose status is shown.
  final ZenSyncTransport transport;

  const ZenSyncStatusBanner({super.key, required this.transport});

  @override
  Widget build(BuildContext context) => StreamBuilder<ZenSyncStatus>(
    stream: transport.statusChanges,
    initialData: transport.status,
    builder: (context, snapshot) {
      final status = snapshot.data ?? transport.status;
      if (status.state != ZenSyncState.unavailable) return const SizedBox.shrink();
      final messages = StoreLocalizations.of(context);
      final scheme = Theme.of(context).colorScheme;
      final text = switch (status.issue) {
        ZenSyncIssue.noAccount => messages.syncNoAccount,
        ZenSyncIssue.keychainUnavailable => messages.syncKeychainUnavailable,
        ZenSyncIssue.accountChanged => messages.syncAccountChanged,
        ZenSyncIssue.cloudDataDeleted => messages.syncCloudDataDeleted,
        ZenSyncIssue.quotaExceeded => messages.syncQuotaExceeded,
        ZenSyncIssue.unreadableRecords => messages.syncUnreadableRecords,
        ZenSyncIssue.other || null => messages.syncOther,
      };
      return Semantics(
        container: true,
        liveRegion: true,
        child: ColoredBox(
          color: scheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.cloud_off, color: scheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(text, style: TextStyle(color: scheme.onTertiaryContainer)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
