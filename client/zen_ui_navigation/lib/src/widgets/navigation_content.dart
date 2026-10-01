import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Wraps the page a navigation menu selects as the `main` landmark, so a screen-reader user can
/// jump past the menu straight to the content.
class NavigationContent extends StatelessWidget {
  /// Wraps [child], the selected destination's page.
  const NavigationContent({required this.child, super.key});

  /// The selected destination's page.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(role: SemanticsRole.main, container: true, explicitChildNodes: true, child: child);
}
