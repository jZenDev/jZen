import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The widest a dialog grows. Form and detail content reads badly stretched across a desktop
/// window, and Material's own dialog default (280 minimum, no maximum) would let it.
const double zenDialogMaxWidth = 560;

/// The margin a dialog keeps from the window edge; a sheet is full height and handles the safe
/// area itself.
const EdgeInsets _dialogInset = EdgeInsets.symmetric(horizontal: 40, vertical: 24);

/// Material bottom sheet, full height. Android.
///
/// Full height because the content is a form or a detail view, and a form that resizes when
/// the keyboard opens is worse than one that already fills the screen.
Future<T?> presentMaterialSheet<T>(
  BuildContext context,
  WidgetBuilder builder,
  bool barrierDismissible,
) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: barrierDismissible,
    enableDrag: barrierDismissible,
    constraints: const BoxConstraints.expand(),
    builder: builder,
  );
}

/// Cupertino sheet. iOS.
Future<T?> presentCupertinoSheet<T>(
  BuildContext context,
  WidgetBuilder builder,
  bool barrierDismissible,
) {
  return showCupertinoSheet<T>(
    context: context,
    enableDrag: barrierDismissible,
    // The content's own scrolling is its business: the controller only matters for coupling a
    // scroll view to the drag-to-dismiss gesture, which a caller can do with its own.
    scrollableBuilder: (BuildContext context, ScrollController _) {
      return _CupertinoSurface(child: Builder(builder: builder));
    },
  );
}

/// Material dialog. Linux, Windows and web.
Future<T?> presentMaterialDialog<T>(
  BuildContext context,
  WidgetBuilder builder,
  bool barrierDismissible,
) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext context) {
      return Dialog(
        insetPadding: _dialogInset,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: zenDialogMaxWidth),
          child: Builder(builder: builder),
        ),
      );
    },
  );
}

/// Cupertino dialog. macOS.
///
/// Flutter's Cupertino widgets emulate iOS, not AppKit, so this is "closer to native than
/// Material on a Mac", not a claim of pixel-correct macOS. A dedicated macOS kit is a separate
/// decision.
Future<T?> presentCupertinoDialog<T>(
  BuildContext context,
  WidgetBuilder builder,
  bool barrierDismissible,
) {
  return showCupertinoDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext context) {
      return Center(
        child: Padding(
          padding: _dialogInset,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: zenDialogMaxWidth),
            child: CupertinoPopupSurface(
              child: _CupertinoSurface(child: Builder(builder: builder)),
            ),
          ),
        ),
      );
    },
  );
}

/// The surface content sits on inside a Cupertino presentation.
///
/// Callers write ordinary Material widgets (a `TextField`, a `ListTile`), and those need a
/// `Material` ancestor that neither Cupertino route provides (and without one, text renders
/// with the yellow double underline of a missing style). It is transparent, so the Cupertino
/// surface behind it is what shows.
class _CupertinoSurface extends StatelessWidget {
  const _CupertinoSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
