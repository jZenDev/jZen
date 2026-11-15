import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_store/zen_ui_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../core/device_session.dart';
import '../l10n/generated/local_localizations.dart';
import 'settings_line.dart';

/// The folder and the pairing for platforms that sync through a folder a sync service of the
/// person's keeps in step: choose it, then make this the first device, join one, or add one.
class SharedFolderControls extends StatelessWidget {
  final DeviceSession session;

  const SharedFolderControls({super.key, required this.session});

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final messages = LocalDemoLocalizations.of(context);
    final folder = session.folder;
    final key = session.syncKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsLine('${messages.syncFolder}: ${folder?.label ?? messages.syncFolderNone}'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ZenButton(
            label: folder == null ? messages.chooseFolder : messages.changeFolder,
            variant: ZenButtonVariant.secondary,
            onPressed: () async {
              final chosen = await session.chooseFolder();
              if (context.mounted && chosen is ZenFailure<bool>) {
                showZenMessage(context, messages.folderFailed(chosen.error.message));
              }
            },
          ),
        ),
        if (key == null) ...[
          SettingsLine(messages.firstDeviceHint),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ZenButton(
              label: messages.firstDevice,
              variant: ZenButtonVariant.secondary,
              onPressed: () async {
                final made = await session.createSyncKey();
                if (!context.mounted) return;
                showZenMessage(context, switch (made) {
                  ZenSuccess() => messages.syncKeyMade,
                  ZenFailure(:final error) => messages.syncKeyFailed(error.message),
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ZenButton(
              label: messages.joinDevice,
              variant: ZenButtonVariant.secondary,
              onPressed: () => _push(
                context,
                ZenJoinScreen(
                  onKey: (joined) async {
                    final adopted = await session.adoptSyncKey(joined);
                    if (context.mounted && adopted is ZenSuccess) {
                      Navigator.of(context).pop();
                      showZenMessage(context, messages.syncKeyJoined);
                    }
                    return adopted;
                  },
                  onCancel: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ZenButton(
              label: messages.addDevice,
              variant: ZenButtonVariant.secondary,
              onPressed: () => _push(
                context,
                ZenAddDeviceScreen(syncKey: key, onClose: () => Navigator.of(context).pop()),
              ),
            ),
          ),
      ],
    );
  }
}
