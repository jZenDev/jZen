import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// Stroke width of [FocusRing]. WCAG 2.2 SC 2.4.13 measures a focus indicator by its area, and a
/// 2 px perimeter is the size that success criterion names.
const double zenFocusRingWidth = 2;

/// Outlines [child] while the control it sits inside holds focus that a keyboard or an assistive
/// technology put there.
///
/// Material 3 marks a focused control with a translucent overlay of about 10% opacity. Against a
/// light surface that is a contrast near 1.2:1, far below the 3:1 WCAG SC 1.4.11 asks of the
/// visual cue that identifies a state, so a keyboard user on desktop or web cannot see where they
/// are. This draws a solid ring in the theme's primary colour on top of that overlay.
///
/// It reads focus from the nearest enclosing [Focus], so it goes *inside* the focusable control —
/// a NavigationRail destination's icon, a button's child — not around it. The ring is painted
/// outside [child]'s bounds and never changes layout. When it shows is [_InputModality]'s call.
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
    _InputModality.attach();
  }

  @override
  void dispose() {
    _InputModality.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _InputModality.instance,
    builder: (context, child) {
      // A dependency, not a one-off read: Focus.maybeOf rebuilds this widget whenever the
      // enclosing node gains or loses focus.
      final bool focused = Focus.maybeOf(context)?.hasFocus ?? false;
      if (!focused || !_InputModality.instance.showsFocus) return child!;

      return Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          child!,
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
    },
    child: widget.child,
  );
}

/// Whether focus should be *shown*: the rule browsers apply as CSS `:focus-visible`.
///
/// Flutter's own [FocusHighlightMode] cannot answer this. It treats a mouse as "traditional" input
/// alongside the keyboard and switches off only for touch, so after a mouse click the ring stayed
/// on whatever held focus — a ring nobody navigating by mouse asked for.
///
/// So this tracks input directly. A key press (not a bare modifier, which is how a click with Cmd
/// or Shift starts) turns the ring on; a pointer press of any kind — mouse, touch, pen — turns it
/// off. And while an assistive technology is attached it stays on regardless: a screen reader or
/// switch device moves focus through the semantics tree without sending key events, and on web
/// that is also when the engine turns semantics on. Before any input at all it is on, so focus an
/// app places programmatically is visible, as `:focus-visible` does.
///
/// One instance serves every ring. Its global listeners exist only while a ring is mounted.
class _InputModality extends ChangeNotifier {
  _InputModality._();

  static final _InputModality instance = _InputModality._();
  static int _rings = 0;

  static final Set<LogicalKeyboardKey> _modifiers = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  };

  bool _keyboard = true;

  /// True after keyboard input, or while an assistive technology is attached.
  bool get showsFocus => _keyboard || SemanticsBinding.instance.semanticsEnabled;

  static void attach() {
    if (_rings++ > 0) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(instance._onPointer);
    HardwareKeyboard.instance.addHandler(instance._onKey);
    SemanticsBinding.instance.addSemanticsEnabledListener(instance.notifyListeners);
  }

  static void detach() {
    if (--_rings > 0) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(instance._onPointer);
    HardwareKeyboard.instance.removeHandler(instance._onKey);
    SemanticsBinding.instance.removeSemanticsEnabledListener(instance.notifyListeners);
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) _set(keyboard: false);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && !_modifiers.contains(event.logicalKey)) _set(keyboard: true);
    // Observes only: the key still reaches whatever handles it.
    return false;
  }

  void _set({required bool keyboard}) {
    if (_keyboard == keyboard) return;
    _keyboard = keyboard;
    notifyListeners();
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
