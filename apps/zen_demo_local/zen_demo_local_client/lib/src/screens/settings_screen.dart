import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../core/device_session.dart';
import '../l10n/generated/local_localizations.dart';
import '../widgets/device_section.dart';
import '../widgets/security_section.dart';
import '../widgets/sync_section.dart';

/// PIN, sync and this device's copy.
class SettingsScreen extends StatelessWidget {
  final DeviceSession session;
  final ZenPinLock lock;

  const SettingsScreen({super.key, required this.session, required this.lock});

  @override
  Widget build(BuildContext context) => ZenPageScaffold(
    title: LocalDemoLocalizations.of(context).settingsTitle,
    // The session changes when a folder is chosen or a key made, and the sections follow it.
    body: ListenableBuilder(
      listenable: session,
      builder: (context, _) => ListView(
        children: [
          SecuritySection(lock: lock),
          SyncSection(session: session),
          DeviceSection(session: session),
        ],
      ),
    ),
  );
}
