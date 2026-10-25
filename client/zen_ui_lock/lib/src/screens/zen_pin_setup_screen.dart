import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/lock_localizations.dart';
import '../l10n/lock_error_text.dart';
import '../state/zen_pin_lock.dart';

/// Sets the PIN, or — when one is set — changes it, asking for the current one first. Open it
/// with `showZenPinSetup`.
class ZenPinSetupScreen extends StatefulWidget {
  /// The lock whose PIN this sets.
  final ZenPinLock lock;

  /// Called once the PIN is saved.
  final VoidCallback onDone;

  const ZenPinSetupScreen({super.key, required this.lock, required this.onDone});

  @override
  State<ZenPinSetupScreen> createState() => _ZenPinSetupScreenState();
}

class _ZenPinSetupScreenState extends State<ZenPinSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  String? _currentError;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _currentError = null;
    });
    final lock = widget.lock;
    final result = lock.isEnabled
        ? await lock.change(_current.text, _next.text)
        : await lock.enable(_next.text);
    if (!mounted) return;
    switch (result) {
      case ZenSuccess():
        widget.onDone();
      case ZenFailure(:final error):
        setState(() {
          _busy = false;
          _currentError = lockErrorText(LockLocalizations.of(context), error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = LockLocalizations.of(context);
    final changing = widget.lock.isEnabled;
    Widget pinField(
      String label,
      TextEditingController controller, {
      String? errorText,
      FormFieldValidator<String>? validator,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ZenTextField(
        label: label,
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        errorText: errorText,
        validator: validator,
      ),
    );
    return ZenPageScaffold(
      title: changing ? messages.changePinTitle : messages.setPinTitle,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (changing) pinField(messages.currentPinLabel, _current, errorText: _currentError),
              pinField(
                messages.newPinLabel,
                _next,
                errorText: changing ? null : _currentError,
                validator: (value) =>
                    ZenPinLock.validate(value ?? '') == null ? null : messages.pinFormat,
              ),
              pinField(
                messages.repeatPinLabel,
                _repeat,
                validator: (value) => value == _next.text ? null : messages.pinsDoNotMatch,
              ),
              ZenButton(
                label: messages.saveButton,
                onPressed: _busy ? null : _save,
                isLoading: _busy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
