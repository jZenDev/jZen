import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import 'focus_ring.dart';

/// A focusable tap target with a visible focus ring and platform interaction style.
///
/// Supply a suitably sized, accessible [child] and a Material ancestor. A null [onTap]
/// disables activation. [borderRadius] controls the Material ink shape.
class AdaptiveInkWell extends StatelessWidget {
  /// Creates an adaptive tap target.
  const AdaptiveInkWell({required this.child, required this.onTap, this.borderRadius, super.key});

  /// The content and accessible label of the target.
  final Widget child;

  /// Called on activation, or null to disable the target.
  final VoidCallback? onTap;

  /// The shape of the Material ink response.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => FocusRing.wrapping(
    child: zenIsApplePlatform
        ? buildCupertinoInkWell(child: child, onTap: onTap, borderRadius: borderRadius)
        : InkWell(onTap: onTap, borderRadius: borderRadius, child: child),
  );
}

/// An ink-free tap target for Cupertino implementations exercised directly in tests.
Widget buildCupertinoInkWell({
  required Widget child,
  required VoidCallback? onTap,
  BorderRadius? borderRadius,
}) => InkWell(
  onTap: onTap,
  borderRadius: borderRadius,
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
  child: child,
);
