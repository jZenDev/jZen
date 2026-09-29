import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// Stroke width of [FocusRing]. WCAG 2.2 SC 2.4.13 measures a focus indicator by its area, and a
/// 2 px perimeter is the size that success criterion names.
const double zenFocusRingWidth = 2;

/// Outlines [child] while the control it sits inside holds keyboard focus.
///
/// Material 3 marks a focused control with a translucent overlay of about 10% opacity. Against a
/// light surface that is a contrast near 1.2:1, far below the 3:1 WCAG SC 1.4.11 asks of the
/// visual cue that identifies a state, so a keyboard user on desktop or web cannot see where they
/// are. This draws a solid ring in the theme's primary colour on top of that overlay.
///
/// It reads focus from the nearest enclosing [Focus], so it goes *inside* the focusable control —
/// a NavigationRail destination's icon, a button's child — not around it. The ring is painted
/// outside [child]'s bounds and never changes layout. It shows only in
/// [FocusHighlightMode.traditional], which is Flutter's own rule for focus highlights: after
/// keyboard input, never after a pointer or touch.
class FocusRing extends StatefulWidget {
  /// Creates a ring around [child].
  const FocusRing({required this.child, super.key});

  /// The content the ring surrounds.
  final Widget child;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) => setState(() {});

  @override
  Widget build(BuildContext context) {
    // A dependency, not a one-off read: Focus.maybeOf rebuilds this widget whenever the enclosing
    // node gains or loses focus.
    final bool focused = Focus.maybeOf(context)?.hasFocus ?? false;
    final bool keyboard = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (!focused || !keyboard) return widget.child;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        widget.child,
        Positioned(
          left: -4,
          top: -4,
          right: -4,
          bottom: -4,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: zenFocusRingWidth,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
      child: FocusTraversalGroup(child: child),
    ),
  );
}

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
