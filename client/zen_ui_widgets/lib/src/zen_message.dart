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
/// [context] must sit below the app's `Navigator` (any screen does) and, on Apple, have an
/// `Overlay`; without one this throws rather than showing nothing.
void showZenMessage(BuildContext context, String message, {Color? backgroundColor}) {
  zenIsApplePlatform
      ? showCupertinoZenMessage(context, message, backgroundColor: backgroundColor)
      : showMaterialZenMessage(context, message, backgroundColor: backgroundColor);
}

/// The Material message. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
void showMaterialZenMessage(BuildContext context, String message, {Color? backgroundColor}) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: backgroundColor));
}

/// The toast on screen, if any: one at a time, so a new message replaces it.
OverlayEntry? _showing;

void _dismiss(OverlayEntry entry) {
  if (identical(_showing, entry)) _showing = null;
  entry.remove();
  entry.dispose();
}

/// The Apple message; see [showMaterialZenMessage].
void showCupertinoZenMessage(BuildContext context, String message, {Color? backgroundColor}) {
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final Color background = backgroundColor ?? scheme.inverseSurface;
  final Color foreground = backgroundColor == null
      ? scheme.onInverseSurface
      : ThemeData.estimateBrightnessForColor(backgroundColor) == Brightness.dark
      ? Colors.white
      : Colors.black;
  final Duration duration = MediaQuery.accessibleNavigationOf(context)
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
      onDismiss: () => _dismiss(entry),
    ),
  );
  _showing = entry;
  overlay.insert(entry);
}
