import 'package:flutter/widgets.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/lock_localizations.dart';
import '../screens/show_zen_pin_screens.dart';
import '../state/zen_pin_lock.dart';

/// The settings row that turns the PIN lock on (asking for a new PIN) and off (asking for the
/// current one). It shows the lock's real state, so a cancelled dialog leaves it where it was.
class ZenPinLockSwitch extends StatelessWidget {
  /// The lock this row controls.
  final ZenPinLock lock;

  const ZenPinLockSwitch({super.key, required this.lock});

  @override
  Widget build(BuildContext context) {
    final messages = LockLocalizations.of(context);
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => ZenSwitchRow(
        label: messages.lockWithPin,
        subtitle: messages.lockWithPinHint,
        value: lock.isEnabled,
        onChanged: (on) => on ? showZenPinSetup(context, lock) : showZenPinOff(context, lock),
      ),
    );
  }
}
