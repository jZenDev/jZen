import 'package:flutter/material.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';
import '../screens/zen_conflicts_screen.dart';
import '../state/zen_conflict_source.dart';

/// Says, for as long as it is true, that some records wait for the person's choice, and opens the
/// list of them. It takes no space when there is nothing to decide.
///
/// Put it where the person will see it on every launch — above the main screen's content, not in
/// a settings page — because a conflict nobody looks at is a choice nobody makes.
class ZenConflictBanner extends StatelessWidget {
  /// The store whose conflicts are counted.
  final ZenStore store;

  /// The collections the list shows, and how to show their records.
  final List<ZenConflictSource> sources;

  const ZenConflictBanner({super.key, required this.store, required this.sources});

  @override
  Widget build(BuildContext context) => StreamBuilder<Set<String>>(
    stream: store.changes,
    builder: (context, _) {
      final count = store.conflictCount;
      if (count == 0) return const SizedBox.shrink();
      final messages = StoreLocalizations.of(context);
      final scheme = Theme.of(context).colorScheme;
      return Semantics(
        container: true,
        liveRegion: true,
        child: ColoredBox(
          color: scheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Icon(Icons.sync_problem, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    messages.bannerText(count),
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
                ZenButton(
                  label: messages.reviewButton,
                  variant: ZenButtonVariant.text,
                  onPressed: () => Navigator.of(context).push(
                    ZenPageRoute<void>(
                      builder: (_) => ZenConflictsScreen(store: store, sources: sources),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
