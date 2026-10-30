import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';

import '../focus_ring.dart';
import 'slider_values.dart';

/// A labelled slider for one number within bounds. Cupertino slider on Apple platforms,
/// Material elsewhere.
///
/// The app owns [value], [min] and [max] and chooses what the number means: the slider shows
/// and announces it through [valueFormatter], so units, rounding and locale-specific separators
/// stay with the app. The slider never reports a value outside `[min, max]`.
///
/// **Bounds and invalid input.** [min] and [max] must be finite with `min < max`, [divisions]
/// positive, and [value] a finite number; each is an assertion in debug builds. In a release
/// build a [value] outside the range is *shown* at the nearest end and a NaN at [min], and the
/// app's [value] is left alone until the user moves the slider. With [divisions] the slider
/// offers only the `divisions + 1` evenly spaced values and reports one of them; without, any
/// value.
///
/// **Keyboard and assistive technology.** The slider is one control announced once — "Volume,
/// slider, 40 percent" — and a screen reader's increment and decrement move it one step (a
/// division; on a continuous Material slider, Flutter's own twentieth of the range). The arrow
/// keys move one step (a division, or a tenth of the range when continuous), Page Up and Page
/// Down a page (about a tenth of the divisions, a quarter of a continuous range), Home and End to
/// the ends. A [FocusRing] marks keyboard focus. The value is also written beside the label, so
/// it never depends on the thumb's position alone.
class ZenSlider extends StatelessWidget {
  /// Creates a slider named [label] choosing a number from [min] to [max].
  const ZenSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.valueFormatter,
    super.key,
  }) : assert(min < max, 'min must be less than max'),
       assert(divisions == null || divisions > 0, 'divisions must be positive');

  /// What the slider sets; also its accessible name.
  final String label;

  /// The current value.
  final double value;

  /// The smallest value.
  final double min;

  /// The largest value.
  final double max;

  /// Called with the value the user chose, always within `[min, max]` and, with [divisions],
  /// one of its steps; null disables the slider.
  final ValueChanged<double>? onChanged;

  /// How many equal steps the range is divided into; null is continuous.
  final int? divisions;

  /// Writes a value as text, for display and for the screen reader. The default prints whole
  /// numbers plainly and others to two places; pass one to add units or localize.
  final String Function(double value)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    assert(zenSliderBoundsAreValid(min, max, divisions), 'invalid slider bounds');
    assert(value.isFinite, 'a slider value must be a finite number');
    final String Function(double) format = valueFormatter ?? zenSliderFormat;
    final double shown = zenSliderClamp(value, min, max);
    final Widget slider = zenIsApplePlatform
        ? buildCupertinoSlider(context, label, shown, min, max, divisions, format, onChanged)
        : buildMaterialSlider(context, label, shown, min, max, divisions, format, onChanged);
    return _frame(context, label, format(shown), onChanged != null, slider);
  }
}

/// The visible caption — the label on the left, the value on the right — above [slider]. The
/// caption is not a reading stop: the slider names itself and carries its value.
Widget _frame(BuildContext context, String label, String valueText, bool enabled, Widget slider) {
  final ThemeData theme = Theme.of(context);
  final Color? color = enabled ? null : theme.disabledColor;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            children: <Widget>[
              Text(label, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
              Text(valueText, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
            ],
          ),
        ),
      ),
      slider,
    ],
  );
}

/// The Material slider. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
///
/// Material's own slider already handles the arrow keys and the screen reader's increment and
/// decrement; it is given a name, its value read through [format], and the Page and Home/End
/// keys it lacks.
Widget buildMaterialSlider(
  BuildContext context,
  String label,
  double value,
  double min,
  double max,
  int? divisions,
  String Function(double) format,
  ValueChanged<double>? onChanged,
) {
  final bool rtl = Directionality.of(context) == TextDirection.rtl;
  return FocusRing.wrapping(
    child: Focus(
      // Catches what the slider leaves unhandled — Page and Home/End, which it does not know —
      // as it bubbles up from the thumb; the arrows stay the slider's own.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (onChanged == null || event is KeyUpEvent) return KeyEventResult.ignored;
        final double? target = zenSliderKeyTarget(
          event.logicalKey,
          arrows: false,
          value: value,
          lowest: min,
          highest: max,
          min: min,
          max: max,
          divisions: divisions,
          rtl: rtl,
        );
        if (target == null) return KeyEventResult.ignored;
        if (target != value) onChanged(target);
        return KeyEventResult.handled;
      },
      child: MergeSemantics(
        child: Semantics(
          label: label,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              semanticFormatterCallback: format,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The Cupertino slider; see [buildMaterialSlider].
///
/// [CupertinoSlider] has no keyboard support and reads its value as a percentage of the range,
/// so it is drawn without semantics of its own: this builds the node — name, value, increment
/// and decrement — and the arrow, Page and Home/End keys.
Widget buildCupertinoSlider(
  BuildContext context,
  String label,
  double value,
  double min,
  double max,
  int? divisions,
  String Function(double) format,
  ValueChanged<double>? onChanged,
) {
  final bool enabled = onChanged != null;
  final bool rtl = Directionality.of(context) == TextDirection.rtl;
  final double step = zenSliderStep(min, max, divisions);
  double moved(double by) => zenSliderSnap(value + by, min, max, divisions);

  return FocusRing.wrapping(
    child: Semantics(
      container: true,
      slider: true,
      enabled: enabled,
      label: label,
      value: format(value),
      increasedValue: format(moved(step)),
      decreasedValue: format(moved(-step)),
      onIncrease: enabled ? () => onChanged(moved(step)) : null,
      onDecrease: enabled ? () => onChanged(moved(-step)) : null,
      child: Focus(
        canRequestFocus: enabled,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (!enabled || event is KeyUpEvent) return KeyEventResult.ignored;
          final double? target = zenSliderKeyTarget(
            event.logicalKey,
            value: value,
            lowest: min,
            highest: max,
            min: min,
            max: max,
            divisions: divisions,
            rtl: rtl,
          );
          if (target == null) return KeyEventResult.ignored;
          if (target != value) onChanged(target);
          return KeyEventResult.handled;
        },
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: CupertinoSlider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
