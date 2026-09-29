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
/// It reads focus from the nearest enclosing [Focus], so the default constructor goes *inside*
/// the focusable control — a NavigationRail destination's icon, a button's child. To ring a whole
/// control instead, put it around the control with [FocusRing.wrapping], which watches for focus
/// anywhere below it. The ring is painted outside [child]'s bounds and never changes layout.
/// When it shows is [_InputModality]'s call.
class FocusRing extends StatefulWidget {
  /// Creates a ring around [child], for use inside the focusable control.
  const FocusRing({required this.child, super.key}) : _wrapping = false;

  /// Creates a ring around [child], a whole control that holds focus itself (a button, a
  /// switch), by watching focus anywhere in [child]'s subtree.
  const FocusRing.wrapping({required this.child, super.key}) : _wrapping = true;

  /// The content the ring surrounds.
  final Widget child;

  final bool _wrapping;

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
  Widget build(BuildContext context) {
    final Widget ring = _ring(widget.child);
    if (!widget._wrapping) return ring;
    // A Focus that cannot take focus itself: hasFocus is still true while a descendant holds
    // it, which is what tells the ring, sitting outside the control, to draw.
    return Focus(canRequestFocus: false, skipTraversal: true, child: ring);
  }

  Widget _ring(Widget content) => ListenableBuilder(
    listenable: _InputModality.instance,
    builder: (context, child) {
      // A dependency, not a one-off read: Focus.maybeOf rebuilds this widget whenever the
      // enclosing node gains or loses focus.
      final bool focused = Focus.maybeOf(context)?.hasFocus ?? false;
      final bool ring = focused && _InputModality.instance.showsFocus;

      // Always a Stack, with the content in the same slot whether or not the ring is drawn.
      // Swapping the bare content for a Stack when focus arrived would remount it, and a
      // control that is remounted while it holds focus loses it. `passthrough` hands the content
      // the constraints the Stack received, so the wrapper never changes its size.
      return Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough,
        children: <Widget>[
          child!,
          if (ring)
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
    child: content,
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
