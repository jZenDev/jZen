import 'package:flutter/material.dart';

import 'zen_page_transitions.dart';

/// A full-screen page route whose transition is [ZenPageTransitions]' for the platform, whatever
/// the application's own `pageTransitionsTheme` says.
///
/// Use it where a screen is pushed with `Navigator.push`, in place of `MaterialPageRoute`, so the
/// package, not each screen or each app, decides what a pushed page does on a Mac.
class ZenPageRoute<T> extends MaterialPageRoute<T> {
  /// Creates a route showing [builder]'s page.
  ZenPageRoute({
    required super.builder,
    super.settings,
    super.requestFocus,
    super.maintainState,
    super.fullscreenDialog,
    super.allowSnapshotting,
    super.barrierDismissible,
  });

  PageTransitionsBuilder? _transition() {
    final TargetPlatform platform = Theme.of(navigator!.context).platform;
    return ZenPageTransitions.theme.builders[platform];
  }

  @override
  Duration get transitionDuration =>
      _transition()?.transitionDuration ?? const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration =>
      _transition()?.reverseTransitionDuration ?? const Duration(milliseconds: 300);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return ZenPageTransitions.theme.buildTransitions<T>(
      this,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        bool allowSnapshotting,
        Widget? child,
      ) {
        final DelegatedTransitionBuilder? delegated = ZenPageTransitions.theme.delegatedTransition(
          Theme.of(context).platform,
        );
        return delegated?.call(context, animation, secondaryAnimation, allowSnapshotting, child);
      };
}
