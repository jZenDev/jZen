import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'l10n/generated/zen_widgets_localizations.dart';

/// Shows [wheel] in a bottom popup with a Done button, the iOS way of choosing a value.
///
/// Completes with what [selection] returns when Done is pressed, and with null if the popup is
/// dismissed by tapping outside it — so a value is only ever committed on purpose.
Future<T?> showWheelPopup<T>(
  BuildContext context, {
  required Widget wheel,
  required T Function() selection,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (BuildContext context) {
      final ZenWidgetsLocalizations strings = ZenWidgetsLocalizations.of(context);
      return ColoredBox(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: SafeArea(
          top: false,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: CupertinoButton(
                    onPressed: () => Navigator.of(context).pop(selection()),
                    child: Text(strings.done),
                  ),
                ),
                SizedBox(height: 216, child: wheel),
              ],
            ),
          ),
        ),
      );
    },
  );
}
