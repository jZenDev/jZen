import 'package:flutter/material.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import '../core/device_session.dart';
import '../l10n/generated/local_localizations.dart';

/// Why sync is stopped, if it is: the transport's own status in words the person can act on, or
/// the reason no transport could be started at all.
class SyncStatusSlot extends StatelessWidget {
  final DeviceSession session;

  const SyncStatusSlot({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final transport = session.transport;
    if (transport != null) return ZenSyncStatusBanner(transport: transport);
    final problem = session.syncProblem;
    if (problem == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Text(
        LocalDemoLocalizations.of(context).syncRefused(problem),
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}
