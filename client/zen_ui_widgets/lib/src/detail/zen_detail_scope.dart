import 'package:flutter/widgets.dart';

/// Marks the subtree of a detail shown beside or over a list by `ZenDetailHost`.
///
/// `ZenPageScaffold` reads it so the detail's first page offers *Close* where a pushed page offers
/// *Back*: the pane has no screen to go back to. `showZenDetail` reads it so a detail opened from
/// inside a detail stacks in that pane instead of replacing it.
class ZenDetailScope extends InheritedWidget {
  /// Creates the scope; [root] is the pane's first page and [close] dismisses the pane.
  const ZenDetailScope({required this.root, required this.close, required super.child, super.key});

  /// The route of the pane's first page.
  final Route<Object?> root;

  /// Dismisses the pane, completing the future `showZenDetail` returned with null.
  final VoidCallback close;

  /// The scope above [context], or null outside a pane.
  static ZenDetailScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ZenDetailScope>();

  /// Whether [context] sits on the pane's first page, where Close replaces Back.
  static bool isRootPage(BuildContext context) {
    final ZenDetailScope? scope = maybeOf(context);
    return scope != null && ModalRoute.of(context) == scope.root;
  }

  @override
  bool updateShouldNotify(ZenDetailScope oldWidget) =>
      root != oldWidget.root || close != oldWidget.close;
}
