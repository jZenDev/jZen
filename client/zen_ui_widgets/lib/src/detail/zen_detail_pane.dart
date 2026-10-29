import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'zen_detail_scope.dart';

/// The content of an open detail: a small navigator of its own, so everything written for a pushed
/// page works in the pane unchanged. `Navigator.pop(result)` completes `showZenDetail`'s future,
/// `Navigator.push` stacks a page in the pane, and a dialog still opens over the whole window.
///
/// The navigator sits above a blank page, which is what lets the detail's first page pop: popping
/// the last page of a navigator is not allowed, popping the one above a blank is.
class ZenDetailPane extends StatefulWidget {
  /// Creates a pane showing [builder]'s page; [onClosed] gets the page's pop result, or null when
  /// the pane was dismissed.
  const ZenDetailPane({required this.builder, required this.onClosed, super.key});

  /// The page.
  final WidgetBuilder builder;

  /// Called when the first page pops, with its result.
  final ValueChanged<Object?> onClosed;

  @override
  State<ZenDetailPane> createState() => _ZenDetailPaneState();
}

class _ZenDetailPaneState extends State<ZenDetailPane> {
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

  void _close() => widget.onClosed(null);

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
            onGenerateInitialRoutes: (NavigatorState _, String _) => <Route<Object?>>[
              _blank,
              _root,
            ],
          ),
        ),
      ),
    );
  }
}
