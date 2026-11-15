import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../../generated/zen_demo_local/v1/chore.pb.dart';
import '../core/priority_label.dart';
import '../l10n/generated/local_localizations.dart';

/// One chore in the list: tap to edit, the trailing button to mark it done or open again.
class ChoreRow extends StatelessWidget {
  final Chore chore;
  final VoidCallback onOpen;
  final VoidCallback onToggleDone;

  const ChoreRow({
    super.key,
    required this.chore,
    required this.onOpen,
    required this.onToggleDone,
  });

  @override
  Widget build(BuildContext context) {
    final messages = LocalDemoLocalizations.of(context);
    final detail = [
      priorityLabel(messages, chore.priority),
      if (chore.note.isNotEmpty) chore.note,
    ].join(' · ');
    return ZenListRow(
      title: chore.title,
      subtitle: detail,
      onTap: onOpen,
      trailing: ZenIconButton(
        icon: chore.done ? Icons.check_circle : Icons.radio_button_unchecked,
        label: chore.done ? messages.choreOpen : messages.choreDone,
        onPressed: onToggleDone,
      ),
    );
  }
}
