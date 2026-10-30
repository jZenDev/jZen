import 'package:flutter/material.dart';

/// How long a section takes to open or close; none at all when the system asks for reduced motion.
const Duration zenExpandableDuration = Duration(milliseconds: 200);

/// The collapsible content of a `ZenExpandableSection`: it grows to its height or shrinks to
/// nothing as [expanded] changes.
///
/// While collapsed it is out of reach: not painted, not hit-testable, and excluded from focus and
/// from assistive technology — a hidden field must not be a tab stop or be read aloud. With
/// [maintainState] false (the default) the [child] is removed from the tree once the collapse
/// finishes and rebuilt on the next expansion, so it starts fresh; with true it stays mounted
/// beside the layout and keeps its state — a half-typed field, a scroll position.
///
/// Internal to the package: not exported.
class ZenExpandableBody extends StatefulWidget {
  /// Creates the body around [child].
  const ZenExpandableBody({
    required this.expanded,
    required this.maintainState,
    required this.child,
    super.key,
  });

  /// Whether the content is shown.
  final bool expanded;

  /// Whether the content keeps its state while collapsed.
  final bool maintainState;

  /// The content.
  final Widget child;

  @override
  State<ZenExpandableBody> createState() => _ZenExpandableBodyState();
}

class _ZenExpandableBodyState extends State<ZenExpandableBody> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: zenExpandableDuration,
    value: widget.expanded ? 1 : 0,
  );
  late final CurvedAnimation _size = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: the change still happens, instantly.
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : zenExpandableDuration;
  }

  @override
  void didUpdateWidget(ZenExpandableBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    if (_controller.duration == Duration.zero) {
      _controller.value = widget.expanded ? 1 : 0;
    } else if (widget.expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _size.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final bool collapsed = _controller.isDismissed;
        if (collapsed && !widget.maintainState) return const SizedBox(width: double.infinity);
        return Offstage(
          offstage: collapsed,
          child: ExcludeFocus(
            excluding: !widget.expanded,
            child: ExcludeSemantics(
              excluding: !widget.expanded,
              child: SizeTransition(
                sizeFactor: _size,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
