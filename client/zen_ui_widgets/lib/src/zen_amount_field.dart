import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'l10n/generated/zen_widgets_localizations.dart';
import 'pair_layout.dart';

final RegExp _grouping = RegExp(r"[\s   ']");
final RegExp _decimal = RegExp(r'^(-?)(\d*)(?:[.,](\d*))?$');

/// The decimal separator [locale] writes: `.` for English, `,` for Ukrainian.
///
/// A locale intl has no number symbols for reads as English rather than throwing, so an app
/// running in a language jZen has never heard of still gets a working field.
String zenDecimalSeparator(Locale locale) {
  final String tag = Intl.verifiedLocale(
    locale.toLanguageTag(),
    NumberFormat.localeExists,
    onFailure: (String _) => 'en',
  )!;
  return NumberFormat.decimalPattern(tag).symbols.DECIMAL_SEP;
}

/// The canonical decimal text — `-1234.56`, dot-separated, no grouping — for what a user typed,
/// or null if [text] is not a number.
///
/// Either `.` or `,` is accepted as the mark, and grouping spaces are ignored, so `1 234,5` and
/// `1234.5` mean the same thing wherever the app is running. The result is text on purpose:
/// what a number *is* — minor units, a decimal type, a `double` — is the application's, and
/// parsing it from a canonical string loses nothing that a float round trip would.
///
/// Returns null for empty text, a bare sign or mark, more than one mark, a `-` when
/// [allowNegative] is false, and more than [maxFractionDigits] fractional digits.
String? normalizeAmount(String text, {int? maxFractionDigits, bool allowNegative = true}) {
  final RegExpMatch? match = _decimal.firstMatch(text.replaceAll(_grouping, ''));
  if (match == null) return null;
  final String sign = match.group(1)!;
  final String whole = match.group(2)!;
  final String fraction = match.group(3) ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  if (sign.isNotEmpty && !allowNegative) return null;
  if (maxFractionDigits != null && fraction.length > maxFractionDigits) return null;
  return '$sign${whole.isEmpty ? '0' : whole}${fraction.isEmpty ? '' : '.$fraction'}';
}

/// [normalizeAmount] as a `double`, for an app that does not need exact decimals; null when
/// [text] is not a number.
double? parseAmount(String text, {int? maxFractionDigits, bool allowNegative = true}) {
  final String? canonical = normalizeAmount(
    text,
    maxFractionDigits: maxFractionDigits,
    allowNegative: allowNegative,
  );
  return canonical == null ? null : double.parse(canonical);
}

/// Keeps a field's text shaped like an amount as it is typed: digits, at most one decimal mark,
/// an optional leading `-`.
///
/// Whichever of `.` or `,` the user types becomes [decimalSeparator], so the field always reads
/// in the locale's own form. An edit that would break the shape — a letter, a second mark, a
/// digit past [maxFractionDigits] — is refused and the previous text stays. Spaces are dropped,
/// so a pasted `1 234` arrives as `1234`.
class ZenAmountInputFormatter extends TextInputFormatter {
  /// Creates a formatter writing [decimalSeparator].
  ZenAmountInputFormatter({
    required this.decimalSeparator,
    this.maxFractionDigits,
    this.allowNegative = true,
  }) : _shape = RegExp(
         '^${allowNegative ? '-?' : ''}\\d*'
         '${maxFractionDigits == 0 ? '' : '(?:${RegExp.escape(decimalSeparator)}\\d*)?'}\$',
       );

  /// The mark the field writes between whole and fractional digits.
  final String decimalSeparator;

  /// The most fractional digits allowed; null for no limit, 0 for whole numbers only.
  final int? maxFractionDigits;

  /// Whether a leading `-` is allowed.
  final bool allowNegative;

  final RegExp _shape;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final String text = newValue.text
        .replaceAll(_grouping, '')
        .replaceAll(RegExp('[.,]'), decimalSeparator);
    if (!_shape.hasMatch(text)) return oldValue;
    if (maxFractionDigits != null) {
      final int mark = text.indexOf(decimalSeparator);
      if (mark >= 0 && text.length - mark - 1 > maxFractionDigits!) return oldValue;
    }
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: newValue.selection.end.clamp(0, text.length)),
    );
  }
}

/// A labelled money-or-quantity field: a decimal keyboard, input shaped by
/// [ZenAmountInputFormatter], the locale's separator, and a localized error when the text is not
/// a number.
///
/// It is the *field and validation shape* only. What the number means — currency, minor units,
/// precision beyond [maxFractionDigits] — stays with the application, which reads the text
/// through [controller] or [onChanged] and [normalizeAmount]. Empty text is valid; whether an
/// empty amount is allowed is the form's rule, not the field's.
///
/// It is a form field, so `Form.validate()` sees it, and its label is the accessible name of
/// the input itself.
class ZenAmountField extends StatelessWidget {
  /// Creates an amount field labelled [label].
  const ZenAmountField({
    required this.label,
    this.controller,
    this.onChanged,
    this.maxFractionDigits,
    this.allowNegative = true,
    this.errorText,
    this.hint,
    this.enabled = true,
    this.textInputAction,
    this.onSubmitted,
    super.key,
  });

  /// The field's name.
  final String label;

  /// Holds the text; the field creates its own if null.
  final TextEditingController? controller;

  /// Called on every change with the canonical text ([normalizeAmount]), or null while the
  /// text is empty or not yet a number.
  final ValueChanged<String?>? onChanged;

  /// The most fractional digits accepted (2 for cents); null for no limit.
  final int? maxFractionDigits;

  /// Whether a leading `-` is accepted.
  final bool allowNegative;

  /// An error the app decides on (a range, a balance), shown instead of the field's own.
  final String? errorText;

  /// Shown, dimmed, while the field is empty.
  final String? hint;

  /// Whether the field takes input.
  final bool enabled;

  /// The keyboard's action key.
  final TextInputAction? textInputAction;

  /// Called with the raw text when the keyboard's action key is pressed.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final ZenWidgetsLocalizations strings = ZenWidgetsLocalizations.of(context);
    // Merged so the error text is read with the field: left beside it, the error sat on a node a
    // screen reader never lands on, and the focused input was named by its label alone.
    return MergeSemantics(
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        forceErrorText: errorText,
        keyboardType: TextInputType.numberWithOptions(
          decimal: maxFractionDigits != 0,
          signed: allowNegative,
        ),
        inputFormatters: <TextInputFormatter>[
          ZenAmountInputFormatter(
            decimalSeparator: zenDecimalSeparator(Localizations.localeOf(context)),
            maxFractionDigits: maxFractionDigits,
            allowNegative: allowNegative,
          ),
        ],
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        onChanged: onChanged == null
            ? null
            : (String text) => onChanged!(
                normalizeAmount(
                  text,
                  maxFractionDigits: maxFractionDigits,
                  allowNegative: allowNegative,
                ),
              ),
        validator: (String? text) {
          if (text == null || text.isEmpty) return null;
          final bool valid =
              normalizeAmount(
                text,
                maxFractionDigits: maxFractionDigits,
                allowNegative: allowNegative,
              ) !=
              null;
          return valid ? null : strings.invalidAmount;
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// A minimum and a maximum — a filter's "from amount" and "to amount" — with the invariant that
/// the minimum does not exceed the maximum enforced in one place.
///
/// Both ends are optional and independent while only one is filled. Once both parse, a minimum
/// above the maximum is called out under the maximum, in words, and the maximum field reports
/// invalid to an enclosing `Form`. Unlike a date range the pair cannot be prevented, only
/// reported, because a number is typed rather than picked.
class ZenAmountRangeField extends StatelessWidget {
  /// Creates a range from [minLabel] to [maxLabel], held in the two controllers.
  const ZenAmountRangeField({
    required this.minLabel,
    required this.maxLabel,
    required this.minController,
    required this.maxController,
    this.maxFractionDigits,
    this.allowNegative = true,
    this.onChanged,
    super.key,
  });

  /// The minimum field's name.
  final String minLabel;

  /// The maximum field's name.
  final String maxLabel;

  /// Holds the minimum's text.
  final TextEditingController minController;

  /// Holds the maximum's text.
  final TextEditingController maxController;

  /// The most fractional digits accepted; null for no limit.
  final int? maxFractionDigits;

  /// Whether a leading `-` is accepted.
  final bool allowNegative;

  /// Called on every change to either end with the canonical text of each ([normalizeAmount]).
  final void Function(String? min, String? max)? onChanged;

  String? _canonical(TextEditingController controller) => normalizeAmount(
    controller.text,
    maxFractionDigits: maxFractionDigits,
    allowNegative: allowNegative,
  );

  @override
  Widget build(BuildContext context) {
    final ZenWidgetsLocalizations strings = ZenWidgetsLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[minController, maxController]),
      builder: (BuildContext context, Widget? _) {
        final String? min = _canonical(minController);
        final String? max = _canonical(maxController);
        final bool inverted = min != null && max != null && double.parse(min) > double.parse(max);

        void changed(String? _) =>
            onChanged?.call(_canonical(minController), _canonical(maxController));

        return ZenPairLayout(
          first: ZenAmountField(
            label: minLabel,
            controller: minController,
            maxFractionDigits: maxFractionDigits,
            allowNegative: allowNegative,
            onChanged: changed,
          ),
          second: ZenAmountField(
            label: maxLabel,
            controller: maxController,
            maxFractionDigits: maxFractionDigits,
            allowNegative: allowNegative,
            errorText: inverted ? strings.invalidAmountRange : null,
            onChanged: changed,
          ),
        );
      },
    );
  }
}
