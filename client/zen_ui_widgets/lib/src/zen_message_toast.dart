import 'dart:async';

import 'package:flutter/material.dart';

/// The transient message `showZenMessage` shows on Apple platforms, where there is no snack bar.
///
/// A rounded pill above the bottom edge, announced as a live region so a screen reader reads it
/// when it appears without moving focus (WCAG 4.1.3). A tap dismisses it, and so does [duration]
/// running out; the timer lives in the widget's state, so it ends with the overlay it sits in. It
/// is placed in an `Overlay` by `showZenMessage`; nothing else builds it.
class ZenMessageToast extends StatefulWidget {
  /// Creates a toast reading [message] on [background], dismissed by [onDismiss] after
  /// [duration] or on a tap.
  const ZenMessageToast({
    required this.message,
    required this.background,
    required this.foreground,
    required this.duration,
    required this.onDismiss,
    super.key,
  });

  /// The text shown and announced.
  final String message;

  /// The pill's colour.
  final Color background;

  /// The text colour; the caller guarantees AA contrast against [background].
  final Color foreground;

  /// How long the toast stays before dismissing itself.
  final Duration duration;

  /// Called when the toast is tapped or its [duration] runs out.
  final VoidCallback onDismiss;

  @override
  State<ZenMessageToast> createState() => _ZenMessageToastState();
}

class _ZenMessageToastState extends State<ZenMessageToast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ZenMessageToast toast = widget;
    final String message = toast.message;
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
              child: Semantics(
                liveRegion: true,
                container: true,
                label: message,
                excludeSemantics: true,
                onTap: toast.onDismiss,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: toast.onDismiss,
                  child: Material(
                    color: toast.background,
                    elevation: 6,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(message, style: style, textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
