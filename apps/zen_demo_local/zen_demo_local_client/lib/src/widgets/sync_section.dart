import 'package:material_ui/material_ui.dart';
import 'package:zen_store_sync/zen_store_sync.dart';

import '../core/device_session.dart';
import '../l10n/generated/local_localizations.dart';
import 'settings_heading.dart';
import 'settings_line.dart';
import 'shared_folder_controls.dart';

/// How this device syncs, in the build's own terms: iCloud on Apple, a folder and a pairing code
/// on Android, Windows and Linux, a development folder with `ZEN_SYNC=folder`.
class SyncSection extends StatelessWidget {
  final DeviceSession session;

  const SyncSection({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final messages = LocalDemoLocalizations.of(context);
    final plan = ZenSync.plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(messages.syncSection),
        switch (plan.kind) {
          ZenSyncKind.sharedFolder => SharedFolderControls(session: session),
          ZenSyncKind.cloudKit => SettingsLine(messages.syncApple),
          ZenSyncKind.folderCloud => SettingsLine(messages.syncDevelopmentFolder),
          null => SettingsLine(messages.syncRefused(plan.refusal ?? '')),
        },
      ],
    );
  }
}
