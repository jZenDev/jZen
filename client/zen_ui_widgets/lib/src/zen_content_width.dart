import 'package:flutter/widgets.dart';

/// Centers page content within a maximum width, with horizontal breathing room.
///
/// Place this inside the page body, and inside a `ZenDetailHost`'s child rather
/// than around the host, so detail placement uses the full available host width.
/// Apply it separately to pushed pages and detail bodies. It does not change
/// `MediaQuery`, so window-based breakpoints remain available to descendants.
class ZenContentWidth extends StatelessWidget {
  /// Creates a content boundary. [maxWidth] includes the content but not the gutter.
  const ZenContentWidth({required this.maxWidth, required this.child, this.gutter = 16, super.key})
    : assert(maxWidth > 0 && maxWidth < double.infinity),
      assert(gutter >= 0 && gutter < double.infinity);

  /// Maximum width of [child], in logical pixels.
  final double maxWidth;

  /// Minimum space on each side, in logical pixels.
  final double gutter;

  /// The page content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}
