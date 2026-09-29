import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import 'focus_ring.dart';
import 'l10n/generated/zen_widgets_localizations.dart';
import 'pair_layout.dart';
import 'picker_field.dart';
import 'wheel_popup.dart';

/// The earliest date a [ZenDateField] offers unless told otherwise.
final DateTime zenDefaultFirstDate = DateTime(2000);

/// The latest date a [ZenDateField] offers unless told otherwise.
final DateTime zenDefaultLastDate = DateTime(2100);

/// A labelled date, chosen from a picker: Material's calendar dialog everywhere except iOS,
/// where it is a wheel. The app owns the value; the field calls [onChanged] with a date-only
/// `DateTime` (midnight, local) and never with a time of day.
///
/// The field is one accessible control — "Due date, 12 Jan 2026, button" — and, when
/// [clearable], a separate "Clear date" button beside it.
class ZenDateField extends StatelessWidget {
  /// Creates a date field labelled [label].
  const ZenDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.clearable = false,
    this.errorText,
    super.key,
  });

  /// The field's name.
  final String label;

  /// The chosen date, or null when none is chosen.
  final DateTime? value;

  /// Called with the chosen date, or null when the user clears the field; null disables it.
  final ValueChanged<DateTime?>? onChanged;

  /// The earliest selectable date; [zenDefaultFirstDate] if omitted.
  final DateTime? firstDate;

  /// The latest selectable date; [zenDefaultLastDate] if omitted.
  final DateTime? lastDate;

  /// Offers a button that empties the field, for a date that is optional.
  final bool clearable;

  /// Why the current date is not acceptable; shown under the field and read with it.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final ZenWidgetsLocalizations strings = ZenWidgetsLocalizations.of(context);
    final DateTime? date = value;
    final bool enabled = onChanged != null;

    final Widget field = ZenPickerField(
      label: label,
      valueText: date == null ? null : MaterialLocalizations.of(context).formatShortDate(date),
      placeholder: strings.selectDate,
      errorText: errorText,
      icon: Icons.calendar_today,
      onTap: enabled ? () => _pick(context) : null,
    );
    if (!clearable || date == null || !enabled) return field;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: field),
        // Beside the field, not inside it: a control nested in another would be a second
        // focus stop announced as part of the first.
        FocusRing.wrapping(
          child: IconButton(
            tooltip: strings.clearDate,
            icon: const Icon(Icons.clear),
            onPressed: () => onChanged!(null),
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final DateTime first = DateUtils.dateOnly(firstDate ?? zenDefaultFirstDate);
    final DateTime last = DateUtils.dateOnly(lastDate ?? zenDefaultLastDate);
    final DateTime? picked = zenIsIOS
        ? await pickCupertinoDate(context, initial: value, first: first, last: last)
        : await pickMaterialDate(context, initial: value, first: first, last: last);
    if (picked != null) onChanged?.call(DateUtils.dateOnly(picked));
  }
}

DateTime _clamp(DateTime? date, DateTime first, DateTime last) {
  final DateTime d = DateUtils.dateOnly(date ?? DateTime.now());
  if (d.isBefore(first)) return first;
  if (d.isAfter(last)) return last;
  return d;
}

/// Material's calendar dialog. Exposed to the package's tests, which cannot reach the branch
/// the host platform did not compile.
Future<DateTime?> pickMaterialDate(
  BuildContext context, {
  required DateTime? initial,
  required DateTime first,
  required DateTime last,
}) {
  return showDatePicker(
    context: context,
    initialDate: _clamp(initial, first, last),
    firstDate: first,
    lastDate: last,
  );
}

/// The iOS date wheel; see [pickMaterialDate].
Future<DateTime?> pickCupertinoDate(
  BuildContext context, {
  required DateTime? initial,
  required DateTime first,
  required DateTime last,
}) {
  DateTime current = _clamp(initial, first, last);
  return showWheelPopup<DateTime>(
    context,
    wheel: CupertinoDatePicker(
      mode: CupertinoDatePickerMode.date,
      initialDateTime: current,
      minimumDate: first,
      maximumDate: last,
      onDateTimeChanged: (DateTime date) => current = date,
    ),
    selection: () => current,
  );
}

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
