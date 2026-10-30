import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../../l10n/generated/demo_localizations.dart';

/// An action menu with enabled and disabled actions, reporting which one was chosen.
class ShowcaseMenuSection extends StatefulWidget {
  const ShowcaseMenuSection({super.key});

  @override
  State<ShowcaseMenuSection> createState() => _ShowcaseMenuSectionState();
}

class _ShowcaseMenuSectionState extends State<ShowcaseMenuSection> {
  String? _chosen;

  @override
  Widget build(BuildContext context) {
    final m = DemoLocalizations.of(context);
    final heading = Theme.of(context).textTheme.titleMedium;
    void choose(String action) => setState(() => _chosen = action);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(m.showcaseMenu, style: heading),
        const SizedBox(height: 8),
        Row(
          children: [
            ZenActionMenu(
              label: m.showcaseMenuLabel,
              actions: [
                ZenMenuAction(
                  label: m.showcaseActionRename,
                  icon: Icons.edit_outlined,
                  onPressed: () => choose(m.showcaseActionRename),
                ),
                ZenMenuAction(
                  label: m.showcaseActionDuplicate,
                  icon: Icons.copy_outlined,
                  onPressed: () => choose(m.showcaseActionDuplicate),
                ),
                // Disabled: shown and announced as unavailable, and never fires.
                ZenMenuAction(
                  label: m.showcaseActionArchive,
                  icon: Icons.archive_outlined,
                  onPressed: null,
                ),
                ZenMenuAction(
                  label: m.showcaseActionDelete,
                  icon: Icons.delete_outline,
                  destructive: true,
                  onPressed: () => choose(m.showcaseActionDelete),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_chosen == null ? m.showcaseMenuNone : m.showcaseMenuChosen(_chosen!)),
            ),
          ],
        ),
      ],
    );
  }
}
