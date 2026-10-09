import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// Arrow keys move focus between navigation destinations.
///
/// The desktop build already maps arrows to directional focus, but a web build maps them to
/// scrolling instead, so on web a keyboard user could only Tab through a menu. Declaring the
/// mapping here makes both builds behave the same. Tab and Shift+Tab are untouched.
const Map<ShortcutActivator, Intent> _arrowKeyFocus = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
  SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
  SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(TraversalDirection.left),
  SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(TraversalDirection.right),
};

/// Wraps a navigation menu so assistive technology and the keyboard treat it as one.
///
/// It is a `navigation` landmark — on web, a `<nav>` element a screen-reader user can jump to —
/// and one focus-traversal group, so Tab visits every destination before leaving for the page,
/// and arrow keys move between destinations (see [_arrowKeyFocus]).
class NavigationRegion extends StatelessWidget {
  /// Wraps [child], the menu of destinations.
  const NavigationRegion({required this.child, super.key});

  /// The menu of destinations.
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    role: SemanticsRole.navigation,
    container: true,
    explicitChildNodes: true,
    child: Shortcuts(
      shortcuts: _arrowKeyFocus,
      child: FocusTraversalOrder(
        order: const NumericFocusOrder(0),
        child: FocusTraversalGroup(child: child),
      ),
    ),
  );
}
