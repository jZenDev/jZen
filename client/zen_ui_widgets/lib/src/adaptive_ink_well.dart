import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

/// A focusable tap target that follows the platform's interaction style.
class AdaptiveInkWell extends StatelessWidget {
  const AdaptiveInkWell({
    required this.child,
    required this.onTap,
    this.borderRadius,
    this.apple = zenIsApplePlatform,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final bool apple;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: borderRadius,
    splashFactory: apple ? NoSplash.splashFactory : null,
    highlightColor: apple ? Colors.transparent : null,
    hoverColor: apple ? Colors.transparent : null,
    child: child,
  );
}
