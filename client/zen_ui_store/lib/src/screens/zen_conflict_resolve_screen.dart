import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';
import '../state/zen_conflict_source.dart';
import '../widgets/zen_conflict_side_card.dart';

/// Every device's version of one record in conflict, side by side, each with a button that keeps
/// it. Opened from `ZenConflictsScreen`.
class ZenConflictResolveScreen extends StatefulWidget {
  /// The conflict shown.
  final ZenConflictView conflict;

  /// Called once a version has been kept.
  final VoidCallback onResolved;

  const ZenConflictResolveScreen({super.key, required this.conflict, required this.onResolved});

  @override
  State<ZenConflictResolveScreen> createState() => _ZenConflictResolveScreenState();
}

class _ZenConflictResolveScreenState extends State<ZenConflictResolveScreen> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _keep(ZenConflictSideView side) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final result = await side.keep();
    if (!mounted) return;
    if (result.isSuccess) {
      widget.onResolved();
    } else {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = StoreLocalizations.of(context);
    final theme = Theme.of(context);
    final title = widget.conflict.title ?? messages.deletedTitle;
    return ZenPageScaffold(
      title: messages.resolveTitle,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(messages.resolveIntro(title), style: theme.textTheme.bodyLarge),
          if (_failed) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                messages.resolveFailed,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ],
          for (final side in widget.conflict.sides) ...[
            const SizedBox(height: 16),
            ZenConflictSideCard(side: side, onKeep: _busy ? null : () => _keep(side)),
          ],
        ],
      ),
    );
  }
}
