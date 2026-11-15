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
/// Close and Escape ask the first page's guard (`PopScope`) before they dismiss, as Back does in a
/// push: a page that vetoes with `canPop: false` is told through `onPopInvokedWithResult` and
/// decides whether to pop itself. A second detail replacing the pane asks the same way
/// ([ZenDetailPaneState.requestClose]). Switching tab discards the pane with its navigator and
/// cannot be vetoed; the page's `State.dispose` is its cleanup hook.
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

  @override
  void initState() {
    super.initState();
    _root.popped.then((Object? result) => widget.onClosed(result));
  }

  /// Dismisses the pane unless its first page vetoes: then the page's `PopScope` is told, and the
  /// pane stays until the page pops itself. Returns whether the pane was dismissed.
  bool requestClose() {
    if (_root.popDisposition == RoutePopDisposition.doNotPop) {
      _root.onPopInvokedWithResult(false, null);
      return false;
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
            onGenerateInitialRoutes: (NavigatorState _, String _) =>
                <Route<Object?>>[_blank, _root],
          ),
        ),
      ),
    );
  }
}
