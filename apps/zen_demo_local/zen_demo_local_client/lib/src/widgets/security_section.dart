import 'package:flutter/material.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import '../l10n/generated/local_localizations.dart';
import 'settings_heading.dart';

/// The PIN switch. Turning it on or off walks through the framework's PIN screens.
class SecuritySection extends StatelessWidget {
  final ZenPinLock lock;

  const SecuritySection({super.key, required this.lock});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsHeading(LocalDemoLocalizations.of(context).securitySection),
      ZenPinLockSwitch(lock: lock),
    ],
  );
}
