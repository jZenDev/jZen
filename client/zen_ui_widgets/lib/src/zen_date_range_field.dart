import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'l10n/generated/zen_widgets_localizations.dart';
import 'pair_layout.dart';
import 'zen_date_field.dart';

/// Two dates that bound a period — a filter's "from" and "to" — with the invariant that the
/// start is not after the end enforced in one place.
///
/// It is enforced two ways. The pickers cannot produce a bad pair: the start picker stops at
/// the end date and the end picker starts at the start date. And a pair handed in that is
/// already inverted (a stale saved filter) is called out under the end field, in words, so the
/// state is never silently accepted.
class ZenDateRangeField extends StatelessWidget {
  /// Creates a range from [fromLabel] to [toLabel].
  const ZenDateRangeField({
    required this.fromLabel,
    required this.toLabel,
    required this.from,
    required this.to,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.clearable = true,
    super.key,
  });

  /// The start field's name.
  final String fromLabel;

  /// The end field's name.
  final String toLabel;

  /// The start of the period, or null for open-ended.
  final DateTime? from;

  /// The end of the period, or null for open-ended.
  final DateTime? to;

  /// Called with the new start and end whenever either changes; null disables the range.
  final void Function(DateTime? from, DateTime? to)? onChanged;

  /// The earliest selectable date; [zenDefaultFirstDate] if omitted.
  final DateTime? firstDate;

  /// The latest selectable date; [zenDefaultLastDate] if omitted.
  final DateTime? lastDate;

  /// Whether either end can be emptied. On by default: a range filter is usually open at one end.
  final bool clearable;

  /// Whether [from] and [to] are both set and in the wrong order.
  bool get isInverted => from != null && to != null && from!.isAfter(to!);

  @override
  Widget build(BuildContext context) {
    final DateTime first = firstDate ?? zenDefaultFirstDate;
    final DateTime last = lastDate ?? zenDefaultLastDate;
    final DateTime? start = from;
    final DateTime? end = to;

    return ZenPairLayout(
      first: ZenDateField(
        label: fromLabel,
        value: start,
        clearable: clearable,
        firstDate: first,
        lastDate: end != null && end.isBefore(last) ? end : last,
        onChanged: onChanged == null ? null : (DateTime? date) => onChanged!(date, end),
      ),
      second: ZenDateField(
        label: toLabel,
        value: end,
        clearable: clearable,
        firstDate: start != null && start.isAfter(first) ? start : first,
        lastDate: last,
        errorText: isInverted ? ZenWidgetsLocalizations.of(context).invalidDateRange : null,
        onChanged: onChanged == null ? null : (DateTime? date) => onChanged!(start, date),
      ),
    );
  }
}
