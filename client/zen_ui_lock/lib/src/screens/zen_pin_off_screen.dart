import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/lock_localizations.dart';
import '../l10n/lock_error_text.dart';
import '../state/zen_pin_lock.dart';

/// Turns the PIN lock off once the current PIN is entered. Open it with `showZenPinOff`.
class ZenPinOffScreen extends StatefulWidget {
  /// The lock to turn off.
  final ZenPinLock lock;

  /// Called once the lock is off.
  final VoidCallback onDone;

  const ZenPinOffScreen({super.key, required this.lock, required this.onDone});

  @override
  State<ZenPinOffScreen> createState() => _ZenPinOffScreenState();
}

class _ZenPinOffScreenState extends State<ZenPinOffScreen> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _turnOff() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await widget.lock.disable(_pin.text);
    if (!mounted) return;
    switch (result) {
      case ZenSuccess():
        widget.onDone();
      case ZenFailure(:final error):
        setState(() {
          _busy = false;
          _error = lockErrorText(LockLocalizations.of(context), error);
        });
        _pin.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = LockLocalizations.of(context);
    return ZenPageScaffold(
      title: messages.turnOffPinTitle,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ZenTextField(
              label: messages.currentPinLabel,
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _turnOff(),
              errorText: _error,
            ),
            const SizedBox(height: 16),
            ZenButton(
              label: messages.turnOffButton,
              onPressed: _busy ? null : _turnOff,
              isLoading: _busy,
            ),
          ],
        ),
      ),
    );
  }
}
