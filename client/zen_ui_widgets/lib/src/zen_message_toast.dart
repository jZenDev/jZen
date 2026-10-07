import 'dart:async';

import 'package:flutter/material.dart';

import 'zen_button.dart';

/// The transient message `showZenMessage` shows on Apple platforms, where there is no snack bar.
///
/// A rounded pill above the bottom edge, announced as a live region so a screen reader reads it
/// when it appears without moving focus (WCAG 4.1.3). A tap dismisses it, and so does [duration]
/// running out; the timer lives in the widget's state, so it ends with the overlay it sits in. It
/// is placed in an `Overlay` by `showZenMessage`; nothing else builds it.
///
/// With an [actionLabel] the pill also holds a button that runs [onAction] and then dismisses the
/// toast. The message stays the live region, read on its own; the button is a separate stop, so
/// a screen reader announces the message and lets the user move to the action. A tap on the
/// message still dismisses.
class ZenMessageToast extends StatefulWidget {
  /// Creates a toast reading [message] on [background], dismissed by [onDismiss] after
  /// [duration] (never, when null) or on a tap.
  const ZenMessageToast({
    required this.message,
    required this.background,
    required this.foreground,
    required this.duration,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// The text shown and announced.
  final String message;

  /// The pill's colour.
  final Color background;

  /// The text colour; the caller guarantees AA contrast against [background].
  final Color foreground;

  /// How long the toast stays before dismissing itself; null stays until dismissed.
  final Duration? duration;

  /// Called when the toast is tapped or its [duration] runs out.
  final VoidCallback onDismiss;

  /// The action button's text and accessible name; null for a toast with no action.
  final String? actionLabel;

  /// Called when the action button is pressed; the toast then dismisses itself.
  final VoidCallback? onAction;

  @override
  State<ZenMessageToast> createState() => _ZenMessageToastState();
}

class _ZenMessageToastState extends State<ZenMessageToast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final Duration? duration = widget.duration;
    if (duration != null) _timer = Timer(duration, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The action: a text [ZenButton] whose colour (and so its focus ring) is the toast's own text
  /// colour, which is already chosen for contrast against the pill. The theme's primary is not:
  /// it is picked for the page, and fails on an app's error red.
  Widget _action(BuildContext context, String label) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Theme(
        data: theme.copyWith(colorScheme: theme.colorScheme.copyWith(primary: widget.foreground)),
        child: ZenButton(
          label: label,
          variant: ZenButtonVariant.text,
          onPressed: () {
            widget.onAction?.call();
            widget.onDismiss();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ZenMessageToast toast = widget;
    final String message = toast.message;
    final String? actionLabel = toast.actionLabel;
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: toast.foreground);
    return Positioned.fill(
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Material(
                color: toast.background,
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Semantics(
                        liveRegion: true,
                        container: true,
                        label: message,
                        excludeSemantics: true,
                        onTap: toast.onDismiss,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: toast.onDismiss,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Text(message, style: style, textAlign: TextAlign.center),
                          ),
                        ),
                      ),
                    ),
                    if (actionLabel != null) _action(context, actionLabel),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
