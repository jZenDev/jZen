import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'zen_detail_scope.dart';

/// The content of an open detail: a small navigator of its own, so everything written for a pushed
/// page works in the pane unchanged. `Navigator.pop(result)` completes `showZenDetail`'s future,
/// `Navigator.push` stacks a page in the pane, and a dialog still opens over the whole window.
///
/// The navigator sits above a blank page, which is what lets the detail's first page pop: popping
/// the last page of a navigator is not allowed, popping the one above a blank is.
///
/// Close and Escape ask the guard (`PopScope`) of every page on the pane's stack, topmost first,
/// before they dismiss, as Back does in a push: a page that vetoes with `canPop: false` is told
/// through `onPopInvokedWithResult` and decides whether to pop itself, and the pages below it are
/// not asked. A second detail replacing the pane asks the same way
/// ([ZenDetailPaneState.requestClose]). A page opened from inside the detail is on that stack, so
/// it guards Escape and a replacing detail like the first page does. Only the first page offers a
/// Close button; a nested page offers Back, which asks that page's guard as always. Switching tab
/// discards the pane with its navigator and cannot be vetoed; the page's `State.dispose` is its
/// cleanup hook.
class ZenDetailPane extends StatefulWidget {
  /// Creates a pane showing [builder]'s page; [onClosed] gets the page's pop result, or null when
  /// the pane was dismissed.
  const ZenDetailPane({
    required this.builder,
    required this.onClosed,
    super.key,
  });

  /// The page.
  final WidgetBuilder builder;

  /// Called when the first page pops, with its result.
  final ValueChanged<Object?> onClosed;

  @override
  State<ZenDetailPane> createState() => ZenDetailPaneState();
}

/// The state of a [ZenDetailPane]; the host asks it to close.
class ZenDetailPaneState extends State<ZenDetailPane> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  late final PageRouteBuilder<Object?> _blank = PageRouteBuilder<Object?>(
    opaque: false,
    transitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
  );
  late final PageRouteBuilder<Object?> _root = PageRouteBuilder<Object?>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (BuildContext context, _, _) => widget.builder(context),
  );

  late final _StackObserver _stack = _StackObserver();

  @override
  void initState() {
    super.initState();
    _root.popped.then((Object? result) => widget.onClosed(result));
  }

  /// Dismisses the pane unless a page on its stack vetoes, asked topmost first: then that page's
  /// `PopScope` is told, and the pane stays until the page pops itself. Returns whether the pane
  /// was dismissed.
  bool requestClose() {
    for (final Route<Object?> route in _stack.routes.reversed) {
      if (route.popDisposition == RoutePopDisposition.doNotPop) {
        route.onPopInvokedWithResult(false, null);
        return false;
      }
    }
    widget.onClosed(null);
    return true;
  }

  void _close() => requestClose();

  @override
  Widget build(BuildContext context) {
    return ZenDetailScope(
      root: _root,
      close: _close,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): _close,
        },
        child: NavigatorPopHandler<Object?>(
          onPopWithResult: (_) => _navigator.currentState?.maybePop(),
          child: Navigator(
            key: _navigator,
            observers: <NavigatorObserver>[_stack],
            onGenerateInitialRoutes: (NavigatorState _, String _) =>
                <Route<Object?>>[_blank, _root],
          ),
        ),
      ),
    );
  }
}

/// Tracks the pages on the pane's navigator, bottom first, so a close can ask each one's guard.
/// The blank page under the first one is not a page of the detail and is left out.
class _StackObserver extends NavigatorObserver {
  final List<Route<Object?>> routes = <Route<Object?>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route as Route<Object?>);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final int at = routes.indexOf(oldRoute as Route<Object?>);
    if (at < 0) return;
    if (newRoute == null) {
      routes.removeAt(at);
    } else {
      routes[at] = newRoute as Route<Object?>;
    }
  }
}
