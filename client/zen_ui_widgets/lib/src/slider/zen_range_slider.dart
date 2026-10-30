import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import 'slider_values.dart';
import 'zen_range_slider_body.dart';

/// A labelled slider for a **lower and an upper bound** within bounds — a price range, a time
/// window. Drawn Cupertino on Apple platforms and Material elsewhere.
///
/// The app owns [values], [min] and [max] and chooses what the numbers mean: they are shown and
/// announced through [valueFormatter], so units and rounding stay with the app.
///
/// **The invariant.** The slider only ever reports a range with `min <= start <= end <= max`.
/// The thumbs may meet — `start == end` is a valid, if narrow, range — but never cross: the start
/// thumb stops at the end value and the end thumb at the start value. Moving one thumb never
/// changes the other. When both sit together, dragging moves the one that can go in the direction
/// of the drag. [min] and [max] must be finite with `min < max` and [divisions] positive; these
/// and `start <= end` are assertions in debug builds. In a release build a [values] outside the
/// range or out of order is *shown* clamped into it and left alone until the user moves a thumb.
///
/// **The thumbs are two controls.** Each has its own tab stop and is announced separately with
/// its own name — [startLabel] and [endLabel], for example "Minimum price" and "Maximum price" —
/// its value and the screen reader's increment and decrement. The arrow keys move the focused
/// thumb one step (a division, or a tenth of the range when continuous), Page Up and Page Down a
/// page, Home and End to the lowest and highest value that thumb may take; a [FocusRing] marks the
/// focused thumb. The current range is also written beside the label.
///
/// Neither idiom's stock range slider can name its thumbs, so both are drawn by the framework from
/// one set of rules; only the track, the thumb and the colours differ between platforms.
class ZenRangeSlider extends StatelessWidget {
  /// Creates a range slider named [label] choosing a range from [min] to [max].
  const ZenRangeSlider({
    required this.label,
    required this.startLabel,
    required this.endLabel,
    required this.values,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.valueFormatter,
    super.key,
  }) : assert(min < max, 'min must be less than max'),
       assert(divisions == null || divisions > 0, 'divisions must be positive');

  /// What the range selects; the name of the group of two thumbs.
  final String label;

  /// The accessible name of the lower thumb, such as "Minimum price".
  final String startLabel;

  /// The accessible name of the upper thumb, such as "Maximum price".
  final String endLabel;

  /// The current range: `start` is the lower bound and `end` the upper.
  final RangeValues values;

  /// The smallest value either thumb can take.
  final double min;

  /// The largest value either thumb can take.
  final double max;

  /// Called with the new range, which always satisfies `min <= start <= end <= max`; null
  /// disables the slider.
  final ValueChanged<RangeValues>? onChanged;

  /// How many equal steps the range is divided into; null is continuous.
  final int? divisions;

  /// Writes a value as text, for display and for the screen reader. The default prints whole
  /// numbers plainly and others to two places; pass one to add units or localize.
  final String Function(double value)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    assert(zenSliderBoundsAreValid(min, max, divisions), 'invalid slider bounds');
    assert(values.start.isFinite && values.end.isFinite, 'range values must be finite');
    assert(values.start <= values.end, 'the start of a range must not exceed its end');
    final String Function(double) format = valueFormatter ?? zenSliderFormat;
    final double start = zenSliderClamp(values.start, min, max);
    final double end = zenSliderClamp(values.end, start, max);
    final RangeValues shown = RangeValues(start, end);
    return zenIsApplePlatform
        ? buildCupertinoRangeSlider(
            context,
            label,
            startLabel,
            endLabel,
            shown,
            min,
            max,
            divisions,
            format,
            onChanged,
          )
        : buildMaterialRangeSlider(
            context,
            label,
            startLabel,
            endLabel,
            shown,
            min,
            max,
            divisions,
            format,
            onChanged,
          );
  }
}

/// The Material slider. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialRangeSlider(
  BuildContext context,
  String label,
  String startLabel,
  String endLabel,
  RangeValues values,
  double min,
  double max,
  int? divisions,
  String Function(double) format,
  ValueChanged<RangeValues>? onChanged,
) => _frame(
  context,
  label,
  values,
  format,
  onChanged != null,
  ZenRangeSliderBody(
    values: values,
    min: min,
    max: max,
    divisions: divisions,
    onChanged: onChanged,
    startLabel: startLabel,
    endLabel: endLabel,
    format: format,
    style: zenMaterialRangeSliderStyle(Theme.of(context)),
  ),
);

/// The Cupertino slider; see [buildMaterialRangeSlider].
Widget buildCupertinoRangeSlider(
  BuildContext context,
  String label,
  String startLabel,
  String endLabel,
  RangeValues values,
  double min,
  double max,
  int? divisions,
  String Function(double) format,
  ValueChanged<RangeValues>? onChanged,
) => _frame(
  context,
  label,
  values,
  format,
  onChanged != null,
  ZenRangeSliderBody(
    values: values,
    min: min,
    max: max,
    divisions: divisions,
    onChanged: onChanged,
    startLabel: startLabel,
    endLabel: endLabel,
    format: format,
    style: zenCupertinoRangeSliderStyle(Theme.of(context)),
  ),
);

/// The group's shell: the visible caption — the label on the left, the range on the right — over
/// [slider]. The group is named once on its own node; the caption is not a reading stop.
Widget _frame(
  BuildContext context,
  String label,
  RangeValues values,
  String Function(double) format,
  bool enabled,
  Widget slider,
) {
  final ThemeData theme = Theme.of(context);
  final TextStyle? style = theme.textTheme.bodyLarge?.copyWith(
    color: enabled ? null : theme.disabledColor,
  );
  return Semantics(
    container: true,
    explicitChildNodes: true,
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              children: <Widget>[
                Text(label, style: style),
                Text('${format(values.start)} – ${format(values.end)}', style: style),
              ],
            ),
          ),
        ),
        slider,
      ],
    ),
  );
}
