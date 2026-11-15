import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../core/device_session.dart';
import '../l10n/generated/local_localizations.dart';
import 'erase_confirmation.dart';
import 'settings_heading.dart';
import 'settings_line.dart';

/// What can be done to this device's own copy: erase it and let the others send it back.
class DeviceSection extends StatelessWidget {
  final DeviceSession session;

  const DeviceSection({super.key, required this.session});

  Future<void> _erase(BuildContext context) async {
    final messages = LocalDemoLocalizations.of(context);
    final confirmed = await showAdaptivePresentation<bool>(
      context,
      builder: (_) => const EraseConfirmation(),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await session.eraseThisDevice();
    if (!context.mounted) return;
    showZenMessage(context, switch (result) {
      ZenSuccess() => messages.erased,
      ZenFailure(:final error) => messages.eraseFailed(error.message),
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = LocalDemoLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(messages.deviceSection),
        SettingsLine(messages.eraseHint),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ZenButton(
            label: messages.eraseCopy,
            variant: ZenButtonVariant.secondary,
            onPressed: () => _erase(context),
          ),
        ),
      ],
    );
  }
}
