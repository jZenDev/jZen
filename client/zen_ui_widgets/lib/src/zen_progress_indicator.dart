import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

/// An indeterminate spinner that renders Cupertino on Apple platforms and Material elsewhere.
///
/// It is decorative: it says nothing to a screen reader, so whatever is loading must be named
/// by its surroundings (a button's label, a screen's title). [size] is the spinner's diameter;
/// [color] defaults to the theme's primary.
class ZenProgressIndicator extends StatelessWidget {
  /// Creates a spinner.
  const ZenProgressIndicator({this.size = 36, this.color, super.key});

  /// The spinner's diameter, in logical pixels.
  final double size;

  /// The spinner's colour; the theme's primary when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: zenIsApplePlatform
            ? buildCupertinoProgress(context, size, color)
            : buildMaterialProgress(context, size, color),
      ),
    );
  }
}

/// The Material spinner. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialProgress(BuildContext context, double size, Color? color) =>
    CircularProgressIndicator(strokeWidth: size <= 24 ? 2 : 4, color: color);

/// The Cupertino spinner; see [buildMaterialProgress].
Widget buildCupertinoProgress(BuildContext context, double size, Color? color) =>
    CupertinoActivityIndicator(
      radius: size / 2,
      color: color ?? Theme.of(context).colorScheme.primary,
    );
