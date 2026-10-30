import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';
import '../state/zen_conflict_source.dart';
import 'zen_conflict_resolve_screen.dart';

/// Every record, across [sources], that waits for the person to choose between devices'
/// versions. Tapping one opens its versions beside the list on a wide window and as a page below.
///
/// It refreshes whenever the store changes, so a conflict resolved here — or on another device
/// and synced in — leaves the list on its own.
class ZenConflictsScreen extends StatefulWidget {
  /// The store the conflicts are in.
  final ZenStore store;

  /// The collections to show, and how to show their records.
  final List<ZenConflictSource> sources;

  const ZenConflictsScreen({super.key, required this.store, required this.sources});

  @override
  State<ZenConflictsScreen> createState() => _ZenConflictsScreenState();
}

class _ZenConflictsScreenState extends State<ZenConflictsScreen> {
  StreamSubscription<Set<String>>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.store.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
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
    return ZenPageScaffold(
      title: messages.conflictsTitle,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              conflicts.isEmpty && failure == null ? messages.noConflicts : messages.conflictsIntro,
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
        ],
      ),
    );
  }
}
