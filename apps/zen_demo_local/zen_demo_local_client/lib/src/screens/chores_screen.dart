import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_ui_store/zen_ui_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../../generated/zen_demo_local/v1/chore.pb.dart';
import '../core/chore_conflict_source.dart';
import '../core/device_session.dart';
import '../l10n/generated/local_localizations.dart';
import '../widgets/chore_list.dart';
import '../widgets/sync_status_slot.dart';
import 'chore_edit_screen.dart';
import 'settings_screen.dart';

/// The home screen: sync and conflict banners, then the chores.
class ChoresScreen extends StatelessWidget {
  final DeviceSession session;
  final ZenPinLock lock;

  const ChoresScreen({super.key, required this.session, required this.lock});

  void _edit(BuildContext context, Chore? chore) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChoreEditScreen(session: session, chore: chore),
    ),
  );

  Future<void> _toggle(BuildContext context, Chore chore) async {
    final messages = LocalDemoLocalizations.of(context);
    final result = await session.chores.edit(chore, chore.deepCopy()..done = !chore.done);
    if (!context.mounted) return;
    if (result.errorOrNull case final error?) {
      showZenMessage(context, switch (error) {
        ZenConflictError() => messages.inConflict,
        ZenNotFoundError() => messages.choreGone,
        _ => messages.saveFailed(error.message),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = LocalDemoLocalizations.of(context);
    // The session replaces its store after an erase, so everything is read through it on each
    // build, and the screen rebuilds when the session or the store's records change.
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => StreamBuilder<Set<String>>(
        stream: session.store.changes,
        builder: (context, _) => ZenPageScaffold(
          title: messages.choresTitle,
          automaticallyImplyLeading: false,
          actions: [
            ZenIconButton(
              icon: Icons.settings,
              label: messages.settings,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(session: session, lock: lock),
                ),
              ),
            ),
          ],
          body: ListView(
            children: [
              SyncStatusSlot(session: session),
              ZenConflictBanner(
                store: session.store,
                sources: choreConflictSources(session, messages),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ZenButton(
                  label: messages.addChore,
                  icon: Icons.add,
                  onPressed: () => _edit(context, null),
                ),
              ),
              ChoreList(
                chores: session.chores.list(),
                onOpen: (chore) => _edit(context, chore),
                onToggleDone: (chore) => _toggle(context, chore),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
