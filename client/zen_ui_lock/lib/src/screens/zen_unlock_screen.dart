import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/lock_localizations.dart';
import '../l10n/lock_error_text.dart';
import '../state/zen_pin_lock.dart';

/// The screen that covers the app until the PIN is entered. `ZenLockGate` shows it; an app does
/// not push it.
///
/// It has no way back on purpose: the only ways past it are the PIN and the device owner's own
/// check ("Forgot PIN?").
class ZenUnlockScreen extends StatefulWidget {
  /// The lock this screen opens.
  final ZenPinLock lock;

  const ZenUnlockScreen({super.key, required this.lock});

  @override
  State<ZenUnlockScreen> createState() => _ZenUnlockScreenState();
}

class _ZenUnlockScreenState extends State<ZenUnlockScreen> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;
  Timer? _waiting;

  @override
  void initState() {
    super.initState();
    _waitOutShutOut();
  }

  @override
  void dispose() {
    _waiting?.cancel();
    _pin.dispose();
    super.dispose();
  }

  /// While attempts are shut out, say so and re-check every second, so the button comes back on
  /// its own when the wait is over.
  void _waitOutShutOut() {
    _waiting?.cancel();
    final wait = widget.lock.retryAfter;
    if (wait == null) return;
    _waiting = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (widget.lock.retryAfter == null) {
        timer.cancel();
        setState(() => _error = null);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _unlock() async {
    if (_busy || widget.lock.retryAfter != null) return;
    setState(() => _busy = true);
    final result = await widget.lock.unlock(_pin.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (result) {
        ZenSuccess() => null,
        ZenFailure(:final error) => lockErrorText(LockLocalizations.of(context), error),
      };
    });
    _pin.clear();
    _waitOutShutOut();
  }

  Future<void> _recover() async {
    final messages = LockLocalizations.of(context);
    setState(() => _busy = true);
    final result = await widget.lock.recover(messages.forgotPinReason);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.isFailure ? messages.ownerNotConfirmed : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = LockLocalizations.of(context);
    final wait = widget.lock.retryAfter;
    final error = wait != null ? messages.lockedOut((wait.inMilliseconds / 1000).ceil()) : _error;
    return ZenPageScaffold(
      title: messages.unlockTitle,
      automaticallyImplyLeading: false,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ZenTextField(
                  label: messages.pinLabel,
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _unlock(),
                  errorText: error,
                  enabled: wait == null,
                ),
                const SizedBox(height: 16),
                ZenButton(
                  label: messages.unlockButton,
                  onPressed: wait == null && !_busy ? _unlock : null,
                  isLoading: _busy,
                ),
                const SizedBox(height: 8),
                ZenButton(
                  label: messages.forgotPinButton,
                  variant: ZenButtonVariant.text,
                  onPressed: _busy ? null : _recover,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
