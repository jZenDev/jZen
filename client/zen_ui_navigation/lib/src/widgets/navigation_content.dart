import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show ZenPageRoute;

import '../zen_navigation_item.dart';

/// Hosts the page a navigation menu selects, as the `main` landmark, in a `Navigator` of its own.
///
/// The landmark lets a screen-reader user jump past the menu straight to the content. The
/// `Navigator` is what keeps a page pushed from the destination inside the content area: without
/// it `Navigator.of(context)` inside a destination is the application's root navigator, and a
/// pushed page fills the window above the menu (ADR-063).
///
/// A page that must cover the menu (a full-screen flow) asks for the root navigator:
/// `Navigator.of(context, rootNavigator: true)`. Dialogs and sheets already do.
///
/// Only the selected destination is built, so choosing another one discards the stack of the one
/// left, as it discards the rest of its state.
class NavigationContent extends StatefulWidget {
  /// Hosts [item]'s page. Keyed by the item's id, so another destination starts a new stack.
  NavigationContent({required this.item}) : super(key: ValueKey<String>(item.id));

  /// The selected destination.
  final ZenNavigationItem item;

  @override
  State<NavigationContent> createState() => _NavigationContentState();
}

class _NavigationContentState extends State<NavigationContent> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  // A `Navigator` focuses its own node when it is built, which would put the first Tab inside
  // the content's focus scope instead of at the menu, and a page with nothing to focus would be a
  // dead end for Tab. So once the first frame has settled focus, it is handed back to where it
  // was; a page pushed later claims focus as any pushed page does. Both frames matter: the
  // `Navigator` applies its autofocus after the frame that built it.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _releaseFocus());
      setState(() {});
    });
  }

  void _releaseFocus() {
    final NavigatorState? navigator = _navigator.currentState;
    if (!mounted || navigator == null) return;
    if (FocusManager.instance.primaryFocus == navigator.focusNode) {
      navigator.focusNode.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    role: SemanticsRole.main,
    container: true,
    explicitChildNodes: true,
    child: FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: Navigator(
        key: _navigator,
        onGenerateRoute: (RouteSettings settings) => ZenPageRoute<void>(
          settings: settings,
          requestFocus: false,
          builder: widget.item.builder,
        ),
      ),
    ),
  );
}
