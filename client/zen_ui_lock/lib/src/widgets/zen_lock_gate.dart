import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../screens/zen_unlock_screen.dart';
import '../state/zen_pin_lock.dart';
import '../state/zen_screen_security.dart';

/// Covers the whole app with the unlock screen while [lock] is locked, and locks it again once
/// the app has been in the background for [relockAfter].
///
/// Put it in `MaterialApp.builder`, so it sits above the navigator and every route: a gate around
/// `home` would leave a pushed page uncovered.
///
/// ```dart
/// MaterialApp(builder: (context, child) => ZenLockGate(lock: lock, child: child!), ...)
/// ```
///
/// While the app is not in front it also draws a plain cover over itself, so the app switcher's
/// snapshot does not show what the PIN protects. The app underneath stays mounted while locked —
/// a half-typed form survives a lock — but it is not painted, not hit-testable and not read by a
/// screen reader.
///
/// With [secureScreen] the app's window is also kept out of screenshots, screen recording and the
/// recents thumbnail on Android (`ZenScreenSecurity`), for as long as the gate is mounted: the
/// app holds data the whole time it is on screen, locked or not.
class ZenLockGate extends StatefulWidget {
  /// The lock that decides whether the app is covered.
  final ZenPinLock lock;

  /// How long the app may be in the background before it locks again. Zero locks it every time.
  final Duration relockAfter;

  /// Whether to set Android's `FLAG_SECURE` while the gate is mounted. Off by default, because a
  /// screenshot is how a person shares a screen on purpose; an application that shows balances,
  /// payees or account numbers turns it on. Nothing happens off Android.
  final bool secureScreen;

  /// The app.
  final Widget child;

  const ZenLockGate({
    super.key,
    required this.lock,
    required this.child,
    this.relockAfter = const Duration(minutes: 1),
    this.secureScreen = false,
  });

  @override
  State<ZenLockGate> createState() => _ZenLockGateState();
}

class _ZenLockGateState extends State<ZenLockGate> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    if (widget.secureScreen) unawaited(ZenScreenSecurity.setSecure(true));
    _lifecycle = AppLifecycleListener(
      onInactive: () {
        // A desktop window that loses focus never becomes hidden unless it is minimised, so the
        // clock starts here: a window left behind another one for an hour must ask for the PIN.
        // On a phone `inactive` also fires for a pulled-down shade or a system dialog, which must
        // not count as leaving the app.
        if (_isDesktop) _hiddenAt ??= DateTime.now();
        setState(() => _covered = true);
      },
      onHide: () => _hiddenAt ??= DateTime.now(),
      onShow: _returned,
      onResume: () {
        _returned();
        setState(() => _covered = false);
      },
    );
  }

  static bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  void _returned() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt != null && DateTime.now().difference(hiddenAt) >= widget.relockAfter) {
      widget.lock.lock();
    }
  }

  @override
  void didUpdateWidget(ZenLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secureScreen != widget.secureScreen) {
      unawaited(ZenScreenSecurity.setSecure(widget.secureScreen));
    }
  }

  @override
  void dispose() {
    if (widget.secureScreen) unawaited(ZenScreenSecurity.setSecure(false));
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.lock,
    builder: (context, _) {
      final locked = widget.lock.isLocked;
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: locked,
            child: TickerMode(enabled: !locked, child: widget.child),
          ),
          // The unlock screen needs an Overlay of its own: above the navigator there is none, and
          // a text field needs one for its cursor and selection handles.
          if (locked)
            Overlay(
              initialEntries: [OverlayEntry(builder: (_) => ZenUnlockScreen(lock: widget.lock))],
            ),
          if (_covered && !locked)
            ExcludeSemantics(child: ColoredBox(color: Theme.of(context).colorScheme.surface)),
        ],
      );
    },
  );
}
