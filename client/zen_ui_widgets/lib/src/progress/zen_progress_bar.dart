import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zen_core/zen_core.dart';

/// The bar's thickness, in logical pixels.
const double _barHeight = 8;

/// A determinate progress bar: how far along something is, from 0 to 1.
///
/// It is for a quantity with a known end, such as a goal reached or a budget spent. For work of
/// unknown length use `ZenProgressIndicator`. A Material bar elsewhere and a rounded pill on Apple
/// platforms, which have no stock bar, chosen on [zenIsApplePlatform].
///
/// * **Name and value.** [label] names what is measured and is required: a bar says nothing to a
///   screen reader on its own. The reader hears it with the value as a percentage in the app's
///   locale ("Groceries, 45%"), as one node; the drawn bar is not a second one.
/// * **Colour** is the theme's primary on a muted track. The fill identifies the quantity, so it
///   meets the 3:1 non-text contrast (WCAG 1.4.11) against the page. [color] overrides it (an
///   over-budget red, say); the app then owns that contrast.
/// * **Range.** [value] is clamped to 0..1, so a goal exceeded still draws a full bar.
class ZenProgressBar extends StatelessWidget {
  /// Creates a bar [value] of the way along, named [label].
  const ZenProgressBar({required this.value, required this.label, this.color, super.key});

  /// How far along, 0 (nothing) to 1 (done); outside that range it is clamped.
  final double value;

  /// What the bar measures, and its accessible name.
  final String label;

  /// The fill's colour; the theme's primary when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final double fraction = value.isNaN ? 0 : value.clamp(0.0, 1.0);
    final Widget bar = zenIsApplePlatform
        ? buildCupertinoProgressBar(context, fraction, color)
        : buildMaterialProgressBar(context, fraction, color);
    return Semantics(
      label: label,
      value: _percent(context, fraction),
      child: ExcludeSemantics(child: bar),
    );
  }
}

/// [fraction] as a percentage written for the app's locale. A locale intl has no number symbols
/// for reads as English rather than throwing.
String _percent(BuildContext context, double fraction) {
  final String tag = Intl.verifiedLocale(
    Localizations.localeOf(context).toLanguageTag(),
    NumberFormat.localeExists,
    onFailure: (String _) => 'en',
  )!;
  return NumberFormat.percentPattern(tag).format(fraction);
}

/// The Material bar. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialProgressBar(BuildContext context, double fraction, Color? color) =>
    LinearProgressIndicator(
      value: fraction,
      minHeight: _barHeight,
      color: color,
      borderRadius: BorderRadius.circular(_barHeight / 2),
    );

/// The Apple bar; see [buildMaterialProgressBar].
Widget buildCupertinoProgressBar(BuildContext context, double fraction, Color? color) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  return ClipRRect(
    borderRadius: BorderRadius.circular(_barHeight / 2),
    child: SizedBox(
      height: _barHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: DecoratedBox(decoration: BoxDecoration(color: color ?? scheme.primary)),
          ),
        ),
      ),
    ),
  );
}
