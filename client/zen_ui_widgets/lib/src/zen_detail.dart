import 'package:flutter/widgets.dart';

import 'zen_detail_host.dart';
import 'zen_detail_scope.dart';
import 'zen_page_route.dart';

/// Opens [builder]'s page as the detail of the list the caller sits in: beside the list when the
/// window is wide, a full-screen push when it is narrow.
///
/// Where it opens, and in which idiom, is the package's decision, not the screen's (ADR-061):
/// an in-layout pane on Apple platforms, a side sheet elsewhere, and a push, with the platform's
/// page transition, when the enclosing [ZenDetailHost] is narrow or there is none.
///
/// The returned future completes with whatever the page passes to `Navigator.pop`, or null when
/// the detail was dismissed (Close, Escape, a second detail replacing it). The page is an ordinary
/// one: a [ZenPageScaffold] offers Close in the pane and Back in a push on its own.
///
/// ```dart
/// final removed = await showZenDetail<bool>(
///   context,
///   builder: (context) => GoalPage(goal: goal),
/// );
/// ```
///
/// Inside a `ZenNavigation` destination the push lands in the content area, so the navigation shell
/// stays visible (ADR-063).
///
/// Opened from inside a detail, the page stacks in that pane.
Future<T?> showZenDetail<T>(BuildContext context, {required WidgetBuilder builder}) {
  if (ZenDetailScope.maybeOf(context) != null) {
    return Navigator.of(context).push<T>(ZenPageRoute<T>(builder: builder));
  }
  final ZenDetailHostState? host = context.findAncestorStateOfType<ZenDetailHostState>();
  if (host != null) return host.show<T>(context, builder);
  return Navigator.of(context).push<T>(ZenPageRoute<T>(builder: builder));
}
