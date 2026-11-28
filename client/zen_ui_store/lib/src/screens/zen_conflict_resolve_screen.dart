import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';
import '../state/zen_conflict_source.dart';
import '../widgets/zen_conflict_side_card.dart';

/// Every version of one record in conflict, side by side, each with a button that keeps it.
/// Opened from `ZenConflictsScreen`.
///
/// A choice is saved only against the versions shown. When the record has changed since — a sync
/// brought another version, or settled it — nothing is written; the screen says so and shows what
/// is there now.
class ZenConflictResolveScreen extends StatefulWidget {
  /// The conflict shown.
  final ZenConflictView conflict;

  /// Called once a version has been kept, or when the person leaves a record that was settled in
  /// the meantime.
  final VoidCallback onResolved;

  const ZenConflictResolveScreen({super.key, required this.conflict, required this.onResolved});

  @override
  State<ZenConflictResolveScreen> createState() => _ZenConflictResolveScreenState();
}

class _ZenConflictResolveScreenState extends State<ZenConflictResolveScreen> {
  /// What is on screen: the conflict the screen was opened with, until a refused choice replaces
  /// it with what the store holds now.
  late ZenConflictView _conflict = widget.conflict;
  bool _busy = false;
  bool _failed = false;
  bool _changed = false;
  bool _settled = false;

  /// Counts the redraws, so that each starts at the top, where it says what happened.
  int _redraws = 0;

  Future<void> _keep(ZenConflictSideView side) async {
    final shown = _conflict;
    setState(() {
      _busy = true;
      _failed = false;
      _changed = false;
    });
    final result = await side.keep();
    if (!mounted) return;
    if (result.isSuccess) {
      widget.onResolved();
      return;
    }
    final latest = shown.isCurrent() ? null : shown.latest();
    setState(() {
      _busy = false;
      switch (latest) {
        case ZenSuccess(data: final now?):
          _conflict = now;
          _changed = true;
          _redraws++;
        case ZenSuccess():
          _settled = true;
          _redraws++;
        case ZenFailure() || null:
          _failed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = StoreLocalizations.of(context);
    final theme = Theme.of(context);
    final title = _conflict.title ?? messages.deletedTitle;
    final problem = _settled
        ? messages.resolveSettled
        : _changed
        ? messages.resolveChanged
        : _failed
        ? messages.resolveFailed
        : null;
    return ZenPageScaffold(
      title: messages.resolveTitle,
      body: ListView(
        key: ValueKey(_redraws),
        padding: const EdgeInsets.all(16),
        children: [
          if (!_settled) Text(messages.resolveIntro(title), style: theme.textTheme.bodyLarge),
          if (problem != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                problem,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ],
          if (_settled) ...[
            const SizedBox(height: 16),
            ZenButton(label: messages.bulkBack, onPressed: widget.onResolved),
          ] else
            for (final side in _conflict.sides) ...[
              const SizedBox(height: 16),
              ZenConflictSideCard(side: side, onKeep: _busy ? null : () => _keep(side)),
            ],
        ],
      ),
    );
  }
}
