import 'package:flutter/material.dart';

import 'l10n/generated/zen_widgets_localizations.dart';
import 'pair_layout.dart';
import 'zen_amount_field.dart';

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
