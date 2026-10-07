import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import 'zen_message_toast.dart';

/// How long a message stays up. Longer with a screen reader or switch access on
/// (`accessibleNavigation`), where reaching and reading it takes more time (WCAG 2.2.1).
const Duration zenMessageDuration = Duration(seconds: 4);

/// Shows a transient [message] over the current screen: a snack bar on Material, a toast on
/// Apple platforms, which have no snack bar.
///
/// It does not depend on the screen having a `Scaffold`, so it works the same under a
/// [ZenPageScaffold]'s Cupertino branch, where a `ScaffoldMessenger` has nothing to show it on.
/// A message replaces any still showing. [backgroundColor] paints the message (an error's colour,
/// say); its text colour is chosen for contrast against it.
///
/// [actionLabel] and [onAction] add one action to the message, such as "Undo" after a delete: a
/// button named [actionLabel] that calls [onAction] and dismisses the message. Give both or
/// neither. The action is a keyboard-reachable button with the framework's focus ring. A message
/// with an action does not time out: a choice that vanishes in four seconds is out of reach of
/// anyone who needs longer (WCAG 2.2.1), so it stays until the action is taken, it is dismissed
/// (the close icon on Material, a tap on Apple) or another message replaces it.
///
/// [context] must sit below the app's `Navigator` (any screen does) and, on Apple, have an
/// `Overlay`; without one this throws rather than showing nothing.
void showZenMessage(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  assert(
    (actionLabel == null) == (onAction == null),
    'actionLabel and onAction go together: a label with nothing to call, or a call nobody can '
    'reach',
  );
  zenIsApplePlatform
      ? showCupertinoZenMessage(
          context,
          message,
          backgroundColor: backgroundColor,
          actionLabel: actionLabel,
          onAction: onAction,
        )
      : showMaterialZenMessage(
          context,
          message,
          backgroundColor: backgroundColor,
          actionLabel: actionLabel,
          onAction: onAction,
        );
}

/// The text colour for [background]: black or white, whichever reads better. Null [background] is
/// the theme's `inverseSurface`, whose own pair is used.
Color _foregroundFor(ColorScheme scheme, Color? background) => background == null
    ? scheme.onInverseSurface
    : ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : Colors.black;

/// The Material message. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
void showMaterialZenMessage(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final Color foreground = _foregroundFor(Theme.of(context).colorScheme, backgroundColor);
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        // An actioned snack bar persists (SnackBar's own default); without a way to close it,
        // it would sit there until another message replaced it.
        showCloseIcon: actionLabel != null,
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                onPressed: onAction!,
                // The default action colour is chosen against the theme's own snack bar, not an
                // app's: on an error red it fails AA.
                textColor: backgroundColor == null ? null : foreground,
              ),
      ),
    );
}

/// The toast on screen, if any: one at a time, so a new message replaces it.
OverlayEntry? _showing;

void _dismiss(OverlayEntry entry) {
  if (identical(_showing, entry)) _showing = null;
  entry.remove();
  entry.dispose();
}

/// The Apple message; see [showMaterialZenMessage].
void showCupertinoZenMessage(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final Color background = backgroundColor ?? scheme.inverseSurface;
  final Color foreground = _foregroundFor(scheme, backgroundColor);
  // A message with an action stays until it is dealt with; see [showZenMessage].
  final Duration? duration = actionLabel != null
      ? null
      : MediaQuery.accessibleNavigationOf(context)
      ? zenMessageDuration * 3
      : zenMessageDuration;

  final OverlayEntry? previous = _showing;
  if (previous != null) _dismiss(previous);

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext context) => ZenMessageToast(
      message: message,
      background: background,
      foreground: foreground,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      onDismiss: () => _dismiss(entry),
    ),
  );
  _showing = entry;
  overlay.insert(entry);
}
