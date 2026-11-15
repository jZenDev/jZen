import 'package:flutter/material.dart';

import '../../generated/zen_demo_local/v1/chore.pb.dart';
import '../l10n/generated/local_localizations.dart';
import 'chore_row.dart';

/// The chores, or a line saying there are none yet.
class ChoreList extends StatelessWidget {
  final List<Chore> chores;
  final ValueChanged<Chore> onOpen;
  final ValueChanged<Chore> onToggleDone;

  const ChoreList({
    super.key,
    required this.chores,
    required this.onOpen,
    required this.onToggleDone,
  });

  @override
  Widget build(BuildContext context) {
    if (chores.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(LocalDemoLocalizations.of(context).emptyChores),
      );
    }
    return Column(
      children: [
        for (final chore in chores)
          ChoreRow(
            key: ValueKey(chore.id),
            chore: chore,
            onOpen: () => onOpen(chore),
            onToggleDone: () => onToggleDone(chore),
          ),
      ],
    );
  }
}
