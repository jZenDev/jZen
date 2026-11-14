import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';

/// Builds a camera view that calls `onCode` with the text of each QR code it reads.
///
/// An application supplies one where the device has a camera (the `mobile_scanner` plugin, ADR-075),
/// because the plugin's permission strings and platform setup belong to the application's own
/// manifest and `Info.plist`, and a Windows or Linux build must not carry a camera plugin it
/// cannot use. The builder renders its own "camera not allowed" message.
typedef ZenQrScannerBuilder = Widget Function(BuildContext context, ValueChanged<String> onCode);

/// Where a new device enters the code shown by `ZenAddDeviceScreen`: scanned with the camera
/// when [scanner] is given, typed always.
///
/// The typed field hides what is typed, which also keeps the keyboard from learning the code,
/// and offers show/hide to check it. On a rejected code it says what is wrong, by group where it
/// can, and keeps nothing of the code. A paste is accepted; the code is never copied *out*.
class ZenJoinScreen extends StatefulWidget {
  /// Receives the sync key a valid code carries; the application keeps it (in the secure store)
  /// and opens the store. A failure is shown, not swallowed, and the code stays to be tried again.
  final Future<ZenResult<void>> Function(List<int> key) onKey;

  /// Called when the person cancels. The application pops the screen.
  final VoidCallback onCancel;

  /// Reads QR codes with a camera; null where the device has none.
  final ZenQrScannerBuilder? scanner;

  /// The clock; tests replace it.
  final DateTime Function() now;

  const ZenJoinScreen({
    super.key,
    required this.onKey,
    required this.onCancel,
    this.scanner,
    this.now = _systemNow,
  });

  @override
  State<ZenJoinScreen> createState() => _ZenJoinScreenState();
}

class _ZenJoinScreenState extends State<ZenJoinScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _scanning = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _explain(StoreLocalizations messages, ZenError error) {
    if (error is! ZenPairingError) return messages.joinFailed(error.message);
    return switch (error.problem) {
      ZenPairingProblem.wrongLength => messages.joinWrongLength,
      ZenPairingProblem.badCharacter => messages.joinBadCharacter,
      ZenPairingProblem.mistyped => messages.joinMistyped(error.group ?? 0),
      ZenPairingProblem.scrambled => messages.joinScrambled,
      ZenPairingProblem.unsupportedVersion => messages.joinUnsupported,
      ZenPairingProblem.expired => messages.joinExpired,
    };
  }

  Future<void> _join(String entered) async {
    if (_busy) return;
    final messages = StoreLocalizations.of(context);
    final accepted = ZenPairing.accept(entered, now: widget.now());
    switch (accepted) {
      case ZenFailure(:final error):
        setState(() {
          _error = _explain(messages, error);
          _scanning = false;
        });
      case ZenSuccess(:final data):
        setState(() {
          _busy = true;
          _error = null;
        });
        final stored = await widget.onKey(data);
        if (!mounted) return;
        setState(() {
          _busy = false;
          if (stored case ZenFailure(:final error)) {
            _error = _explain(messages, error);
          } else {
            _controller.clear();
          }
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = StoreLocalizations.of(context);
    final theme = Theme.of(context);
    final scanner = widget.scanner;
    return ZenPageScaffold(
      title: messages.joinTitle,
      onBack: widget.onCancel,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(messages.joinIntro, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 24),
          if (_scanning && scanner != null)
            SizedBox(height: 320, child: scanner(context, _join))
          else
            ZenTextField(
              label: messages.pairingCodeLabel,
              hint: messages.joinCodeHint,
              controller: _controller,
              errorText: _error,
              obscureText: true,
              revealable: true,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCase()],
              onSubmitted: _join,
            ),
          if (_scanning && _error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 16),
          if (!_scanning)
            ZenButton(
              label: messages.joinButton,
              isLoading: _busy,
              onPressed: () => _join(_controller.text),
            ),
          if (scanner != null) ...[
            const SizedBox(height: 8),
            ZenButton(
              label: _scanning ? messages.typeInsteadButton : messages.scanButton,
              variant: ZenButtonVariant.secondary,
              onPressed: _busy ? null : () => setState(() => _scanning = !_scanning),
            ),
          ],
          const SizedBox(height: 8),
          ZenButton(
            label: messages.cancelButton,
            variant: ZenButtonVariant.text,
            onPressed: widget.onCancel,
          ),
        ],
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

DateTime _systemNow() => DateTime.now();
