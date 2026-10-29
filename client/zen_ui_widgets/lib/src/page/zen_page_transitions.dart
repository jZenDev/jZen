import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

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

/// Which transition a pushed page has on each platform (ADR-061, ADR-062).
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
/// | web, in any browser | Flutter's own default, even in a browser on a Mac |
///
/// "macOS" is the build's `ZEN_PLATFORM`, not the runtime `TargetPlatform`: Flutter reports
/// `TargetPlatform.macOS` for a browser on a Mac too, but a web build renders Material, so it is
/// not a native Mac window and gets no fade.
///
/// Pages the framework pushes ([ZenPageRoute], the narrow case of `showZenDetail`) use [theme]
/// already. An application passes it to `ThemeData.pageTransitionsTheme` so the
/// `MaterialPageRoute`s it still writes follow the same rule.
abstract final class ZenPageTransitions {
  /// The per-platform transitions of this build, for `ThemeData.pageTransitionsTheme`.
  static final PageTransitionsTheme theme = themeFor(macOS: zenIsMacOS);

  /// The transitions for a build that is, or is not, a native macOS one. [theme] is this with the
  /// build's own value; it is a function so a test reaches both from one run.
  static PageTransitionsTheme themeFor({required bool macOS}) => PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      ...const PageTransitionsTheme().builders,
      if (macOS) TargetPlatform.macOS: const ZenFadePageTransitionsBuilder(),
    },
  );
}
