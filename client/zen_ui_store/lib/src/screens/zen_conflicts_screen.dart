import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';
import '../state/zen_conflict_source.dart';
import '../state/zen_conflict_sweep.dart';
import '../state/zen_issue_source.dart';
import 'zen_conflict_bulk_screen.dart';
import 'zen_conflict_resolve_screen.dart';
import 'zen_issue_screen.dart';

/// Every record, across [sources], that waits for the person to choose between devices'
/// versions. Tapping one opens its versions beside the list on a wide window and as a page below.
///
/// When the same two devices disagree on several records, a row above the list settles all of
/// them with one choice ([ZenConflictBulkScreen]).
///
/// The application's own [issues] are listed with them, each opening the application's words and
/// actions, because "what needs my choice" belongs in one place.
///
/// It refreshes whenever the store changes, so a conflict resolved here — or on another device
/// and synced in — leaves the list on its own.
class ZenConflictsScreen extends StatefulWidget {
  /// The store the conflicts are in.
  final ZenStore store;

  /// The collections to show, and how to show their records.
  final List<ZenConflictSource> sources;

  /// Problems only the application can see, shown beside the store's conflicts.
  final List<ZenIssueSource> issues;

  const ZenConflictsScreen({
    super.key,
    required this.store,
    required this.sources,
    this.issues = const [],
  });

  @override
  State<ZenConflictsScreen> createState() => _ZenConflictsScreenState();
}

class _ZenConflictsScreenState extends State<ZenConflictsScreen> {
  final List<StreamSubscription<void>> _changes = [];

  @override
  void initState() {
    super.initState();
    void refresh(void _) {
      if (mounted) setState(() {});
    }

    _changes.add(widget.store.changes.listen(refresh));
    for (final source in widget.issues) {
      if (source.changes?.listen(refresh) case final subscription?) _changes.add(subscription);
    }
  }

  @override
  void dispose() {
    for (final subscription in _changes) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = StoreLocalizations.of(context);
    final theme = Theme.of(context);
    final conflicts = <ZenConflictView>[];
    String? failure;
    for (final source in widget.sources) {
      switch (source.views(notSet: messages.notSet)) {
        case ZenSuccess(:final data):
          conflicts.addAll(data);
        case ZenFailure(:final error):
          failure ??= error.message;
      }
    }
    final issues = [for (final source in widget.issues) ...source.issues()];
    final sweeps = ZenConflictSweep.of(conflicts, thisDevice: widget.store.deviceId);
    return ZenPageScaffold(
      title: messages.conflictsTitle,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              conflicts.isEmpty && issues.isEmpty && failure == null
                  ? messages.noConflicts
                  : issues.isEmpty
                  ? messages.conflictsIntro
                  : messages.attentionIntro,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                failure,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          // Many records two devices disagree on, settled with one choice instead of one tap each.
          for (final sweep in sweeps)
            ZenListRow(
              title: messages.bulkRowTitle(sweep.included.length, sweep.first.$2, sweep.second.$2),
              subtitle: messages.bulkRowSubtitle,
              onTap: () => showZenDetail<void>(
                context,
                builder: (page) => ZenConflictBulkScreen(
                  sweep: sweep,
                  onDone: () => Navigator.of(page).maybePop(),
                ),
              ),
            ),
          for (final conflict in conflicts)
            ZenListRow(
              title: conflict.title ?? messages.deletedTitle,
              subtitle: conflict.sides.map((side) => side.deviceName).join(' · '),
              onTap: () => showZenDetail<void>(
                context,
                builder: (page) => ZenConflictResolveScreen(
                  conflict: conflict,
                  onResolved: () => Navigator.of(page).maybePop(),
                ),
              ),
            ),
          for (final issue in issues)
            ZenListRow(
              title: issue.title,
              subtitle: issue.description,
              // An action need not write to the store, so nothing else would tell this list that
              // the issue is gone: look again once the detail closes.
              onTap: () =>
                  showZenDetail<void>(
                    context,
                    builder: (page) =>
                        ZenIssueScreen(issue: issue, onDone: () => Navigator.of(page).maybePop()),
                  ).whenComplete(() {
                    if (mounted) setState(() {});
                  }),
            ),
        ],
      ),
    );
  }
}
