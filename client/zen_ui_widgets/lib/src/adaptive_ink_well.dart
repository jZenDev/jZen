import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

/// A focusable tap target that follows the platform's interaction style.
class AdaptiveInkWell extends StatelessWidget {
  const AdaptiveInkWell({required this.child, required this.onTap, this.borderRadius, super.key});

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => zenIsApplePlatform
      ? buildCupertinoInkWell(child: child, onTap: onTap, borderRadius: borderRadius)
      : InkWell(onTap: onTap, borderRadius: borderRadius, child: child);
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
