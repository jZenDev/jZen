import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';
import '../state/zen_conflict_source.dart';
import '../state/zen_conflict_sweep.dart';

/// One choice for many records: every record the same two devices changed differently, settled
/// with one device's version, after saying how many and whose.
///
/// It lists the records the choice settles, and names the ones it leaves — a delete against an
/// edit, a record a third device also changed, or one with several versions from one device — so
/// nothing is settled that the person was not shown. Opened from `ZenConflictsScreen`.
class ZenConflictBulkScreen extends StatefulWidget {
  /// The records and the pair of devices the choice is between.
  final ZenConflictSweep sweep;

  /// Called when the person leaves the screen: after every record was settled, or on "Back".
  final VoidCallback onDone;

  const ZenConflictBulkScreen({super.key, required this.sweep, required this.onDone});

  @override
  State<ZenConflictBulkScreen> createState() => _ZenConflictBulkScreenState();
}

class _ZenConflictBulkScreenState extends State<ZenConflictBulkScreen> {
  bool _busy = false;
  ZenSweepOutcome? _unfinished;

  Future<void> _keep(String device) async {
    setState(() => _busy = true);
    final outcome = await widget.sweep.keep(device);
    if (!mounted) return;
    if (outcome.isComplete) {
      widget.onDone();
    } else {
      setState(() {
        _busy = false;
        _unfinished = outcome;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = StoreLocalizations.of(context);
    final theme = Theme.of(context);
    final sweep = widget.sweep;
    final count = sweep.included.length;
    final unfinished = _unfinished;
    String title(ZenConflictView conflict) => conflict.title ?? messages.deletedTitle;
    String keepLabel((String, String) device) => sweep.isThisDevice(device.$1)
        ? messages.bulkKeepThisDevice(count, device.$2)
        : messages.bulkKeepDevice(count, device.$2);
    return ZenPageScaffold(
      title: messages.bulkTitle,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            messages.bulkIntro(count, sweep.first.$2, sweep.second.$2),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          if (unfinished != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                messages.bulkResult(unfinished.settled, unfinished.total),
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
              ),
            ),
            const SizedBox(height: 16),
            ZenButton(label: messages.bulkBack, onPressed: widget.onDone),
          ] else ...[
            for (final device in [sweep.first, sweep.second]) ...[
              ZenButton(
                label: keepLabel(device),
                variant: sweep.isThisDevice(device.$1)
                    ? ZenButtonVariant.primary
                    : ZenButtonVariant.secondary,
                onPressed: _busy ? null : () => _keep(device.$1),
              ),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text(messages.bulkIncludedHeading(count), style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          for (final conflict in sweep.included)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(title(conflict), style: theme.textTheme.bodyLarge),
            ),
          if (sweep.left.isNotEmpty) ...[
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                messages.bulkLeftHeading(sweep.left.length),
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(messages.bulkLeftIntro, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            for (final conflict in sweep.left)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(title(conflict), style: theme.textTheme.bodyLarge),
              ),
          ],
        ],
      ),
    );
  }
}
