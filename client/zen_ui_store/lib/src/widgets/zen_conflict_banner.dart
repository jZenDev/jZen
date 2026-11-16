import 'package:material_ui/material_ui.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';
import '../screens/zen_conflicts_screen.dart';
import '../state/zen_conflict_source.dart';
import '../state/zen_issue_source.dart';

/// Says, for as long as it is true, that some records wait for the person's choice, and opens the
/// list of them. It takes no space when there is nothing to decide.
///
/// The count is the store's conflicts plus whatever the application's [issues] report, so there is
/// one place that says "something needs your choice", not one per kind of problem.
///
/// Put it where the person will see it on every launch — above the main screen's content, not in
/// a settings page — because a conflict nobody looks at is a choice nobody makes.
class ZenConflictBanner extends StatelessWidget {
  /// The store whose conflicts are counted.
  final ZenStore store;

  /// The collections the list shows, and how to show their records.
  final List<ZenConflictSource> sources;

  /// Problems only the application can see, shown beside the store's conflicts.
  final List<ZenIssueSource> issues;

  const ZenConflictBanner({
    super.key,
    required this.store,
    required this.sources,
    this.issues = const [],
  });

  @override
  Widget build(BuildContext context) => _rebuildOn(
    issues,
    (context) => StreamBuilder<Set<String>>(
      stream: store.changes,
      builder: (context, _) => _banner(context),
    ),
    context,
  );

  /// [builder]'s widget, rebuilt too whenever one of [sources] says its answer may have changed.
  static Widget _rebuildOn(
    List<ZenIssueSource> sources,
    WidgetBuilder builder,
    BuildContext context,
  ) {
    var build = builder;
    for (final source in sources) {
      final inner = build;
      final changes = source.changes;
      if (changes == null) continue;
      build = (context) =>
          StreamBuilder<void>(stream: changes, builder: (context, _) => inner(context));
    }
    return build(context);
  }

  Widget _banner(BuildContext context) {
    final issueCount = ZenIssueSource.countIn(issues);
    final count = store.conflictCount + issueCount;
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
                  issueCount == 0 ? messages.bannerText(count) : messages.bannerAttention(count),
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              ZenButton(
                label: messages.reviewButton,
                variant: ZenButtonVariant.text,
                onPressed: () => Navigator.of(context).push(
                  ZenPageRoute<void>(
                    builder: (_) =>
                        ZenConflictsScreen(store: store, sources: sources, issues: issues),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
