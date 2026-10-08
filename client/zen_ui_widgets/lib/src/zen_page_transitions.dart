import 'package:flutter/material.dart';

/// A pushed page that fades in over the one beneath it, with no slide: the transition of a desktop
/// window whose content changes, rather than of a phone whose screen is replaced.
class ZenFadePageTransitionsBuilder extends PageTransitionsBuilder {
  /// Creates the fade transition.
  const ZenFadePageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: child,
    );
  }
}

/// Which transition a pushed page has on each platform (ADR-061).
///
/// Flutter's default puts the iOS slide on macOS too, because macOS is "Cupertino" to it. A Mac
/// window is not a phone: its sidebar switches content without a slide, and a slide-in with an
/// edge-swipe back is the iOS / iPadOS idiom. So the framework decides it once:
///
/// | Platform | Pushed page |
/// |---|---|
/// | iOS | the Cupertino slide, with its edge-swipe back |
/// | macOS | a short fade ([ZenFadePageTransitionsBuilder]) |
/// | Android, Windows, Linux | Flutter's own default for each |
///
/// Pages the framework pushes ([ZenPageRoute], the narrow case of `showZenDetail`) use [theme]
/// already. An application passes it to `ThemeData.pageTransitionsTheme` so the
/// `MaterialPageRoute`s it still writes follow the same rule.
abstract final class ZenPageTransitions {
  /// The per-platform transitions, for `ThemeData.pageTransitionsTheme`.
  static final PageTransitionsTheme theme = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      ...const PageTransitionsTheme().builders,
      TargetPlatform.macOS: const ZenFadePageTransitionsBuilder(),
    },
  );
}
