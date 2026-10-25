import 'package:flutter/widgets.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../state/zen_pin_lock.dart';
import 'zen_pin_off_screen.dart';
import 'zen_pin_setup_screen.dart';

/// Opens the screen that sets the PIN, or changes it when one is set, as a sheet on a phone and a
/// dialog on a desktop. Completes with true once a PIN was saved.
Future<bool> showZenPinSetup(BuildContext context, ZenPinLock lock) async =>
    await showAdaptivePresentation<bool>(
      context,
      builder: (sheet) =>
          ZenPinSetupScreen(lock: lock, onDone: () => Navigator.of(sheet).pop(true)),
    ) ??
    false;

/// Opens the screen that turns the PIN lock off. Completes with true once it is off.
Future<bool> showZenPinOff(BuildContext context, ZenPinLock lock) async =>
    await showAdaptivePresentation<bool>(
      context,
      builder: (sheet) => ZenPinOffScreen(lock: lock, onDone: () => Navigator.of(sheet).pop(true)),
    ) ??
    false;
