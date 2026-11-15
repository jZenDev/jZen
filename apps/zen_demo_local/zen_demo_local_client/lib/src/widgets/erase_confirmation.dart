import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/local_localizations.dart';

/// The question before this device's copy is erased. Pops `true` only on Erase.
class EraseConfirmation extends StatelessWidget {
  const EraseConfirmation({super.key});

  @override
  Widget build(BuildContext context) {
    final messages = LocalDemoLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(messages.eraseConfirmTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(messages.eraseConfirmBody),
          const SizedBox(height: 16),
          ZenButton(label: messages.erase, onPressed: () => Navigator.of(context).pop(true)),
          const SizedBox(height: 8),
          ZenButton(
            label: messages.cancel,
            variant: ZenButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
