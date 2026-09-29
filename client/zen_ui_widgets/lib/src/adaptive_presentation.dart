import 'package:flutter/widgets.dart';
import 'package:zen_core/zen_core.dart';

import 'presenters.dart';

/// Shows [builder]'s content as an overlay that suits the platform: a sheet on touch-first
/// native platforms, a dialog everywhere else, in the Cupertino idiom on Apple platforms and in
/// Material elsewhere.
///
/// | Platform            | Presentation      |
/// |---------------------|-------------------|
/// | Android             | Material bottom sheet |
/// | iOS                 | Cupertino sheet   |
/// | macOS               | Cupertino dialog  |
/// | Linux, Windows, web | Material dialog   |
///
/// The choice is made on `zenIsMobile` and `zenIsApplePlatform`, which are compile-time
/// constants (`ZEN_PLATFORM`), so each build folds this to a single branch and tree-shakes the
/// presentations it never takes. It is deliberately not a `MediaQuery` decision: web and desktop
/// get the dialog at every window size, and a phone never gets one. Web is a dialog because
/// `zenIsMobile` is the constant that separates "touch-first native" from everything else,
/// and a browser on a phone is not native.
///
/// The returned future completes with whatever is passed to `Navigator.pop` when the overlay
/// closes, or `null` if it was dismissed.
///
/// [builder] supplies only the content. The overlay owns its own chrome (surface, size limits,
/// barrier, dismissal), so the same content looks at home on every platform without the caller
/// branching on any of it.
///
/// ```dart
/// final saved = await showAdaptivePresentation<bool>(
///   context,
///   builder: (context) => EditForm(onSaved: () => Navigator.of(context).pop(true)),
/// );
/// ```
///
/// Set [barrierDismissible] to `false` to force the user through the content's own actions.
/// It only governs the tap-outside gesture on dialogs and Android sheets; a Cupertino sheet
/// is dismissed by dragging down, which [barrierDismissible] also disables.
Future<T?> showAdaptivePresentation<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  // ZEN_PLATFORM must be set: with it unset every constant below is false and the caller
  // would silently get the Material dialog on a phone.
  assert(zenPlatform.isNotEmpty, 'ZEN_PLATFORM must be set at compile time');
  if (zenIsMobile) {
    return zenIsApplePlatform
        ? presentCupertinoSheet<T>(context, builder, barrierDismissible)
        : presentMaterialSheet<T>(context, builder, barrierDismissible);
  }
  return zenIsApplePlatform
      ? presentCupertinoDialog<T>(context, builder, barrierDismissible)
      : presentMaterialDialog<T>(context, builder, barrierDismissible);
}
