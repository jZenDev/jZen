import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';
import '../state/zen_conflict_source.dart';

/// One device's version of a record in conflict: where and when it was written, what it holds in
/// the disputed fields (or that it is a delete), and the button that keeps it.
class ZenConflictSideCard extends StatelessWidget {
  /// The version shown.
  final ZenConflictSideView side;

  /// Keeps this version; null while a choice is being saved.
  final VoidCallback? onKeep;

  const ZenConflictSideCard({super.key, required this.side, required this.onKeep});

  @override
  Widget build(BuildContext context) {
    final messages = StoreLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final time = DateFormat.yMMMd(locale).add_Hm().format(side.at);
    // A container with explicit child nodes, so the heading, each field and the button are read as
    // what they are; without it they all merge into the list item, which then announces itself
    // as one button that is also a heading.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  messages.sideHeading(side.deviceName, time),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 12),
              if (side.isDelete)
                Text(messages.deletedHere, style: theme.textTheme.bodyLarge)
              else
                for (final (label, value) in side.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    // One node per field, read as "label, value", rather than two a screen reader
                    // would land on separately.
                    child: MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(value, style: theme.textTheme.bodyLarge),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
              ZenButton(
                label: side.isDelete ? messages.keepDeleted : messages.keepThisVersion,
                variant: ZenButtonVariant.secondary,
                onPressed: onKeep,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
