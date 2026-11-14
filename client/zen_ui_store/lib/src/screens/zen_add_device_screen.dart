import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';
import '../widgets/zen_pairing_code_view.dart';

/// Shows the code a new device joins with, for as long as it is valid.
///
/// Nothing is drawn until the person asks, so opening the screen in a room does not display the
/// key. The code goes away on its own when it expires, and when the app leaves the screen, and
/// Cancel closes the screen; each way back to a code is the explicit "Show a New Code". The key
/// is held only in memory for as long as the screen is open and the code is never logged, put in
/// a URL or offered to the clipboard.
class ZenAddDeviceScreen extends StatefulWidget {
  /// The 32-byte sync key this device holds.
  final List<int> syncKey;

  /// Called when the person cancels. The application pops the screen.
  final VoidCallback onClose;

  /// Whether to draw the QR code beside the typed code.
  final bool showQr;

  /// The clock; tests replace it.
  final DateTime Function() now;

  const ZenAddDeviceScreen({
    super.key,
    required this.syncKey,
    required this.onClose,
    this.showQr = true,
    this.now = _systemNow,
  });

  @override
  State<ZenAddDeviceScreen> createState() => _ZenAddDeviceScreenState();
}

enum _Phase { idle, showing, expired, hidden }

class _ZenAddDeviceScreenState extends State<ZenAddDeviceScreen> with WidgetsBindingObserver {
  _Phase _phase = _Phase.idle;
  ZenPairingOffer? _offer;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || _phase != _Phase.showing) return;
    // Leaving the screen is when a code is photographed or caught in a task switcher.
    _end(_Phase.hidden);
  }

  void _show() {
    final offer = ZenPairing.offer(widget.syncKey, now: widget.now());
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!widget.now().isBefore(offer.expiresAt)) {
        _end(_Phase.expired);
      } else {
        setState(() {});
      }
    });
    setState(() {
      _offer = offer;
      _phase = _Phase.showing;
    });
  }

  void _end(_Phase phase) {
    _tick?.cancel();
    if (!mounted) return;
    setState(() {
      _offer = null;
      _phase = phase;
    });
  }

  String _remaining(ZenPairingOffer offer) {
    final left = offer.expiresAt.difference(widget.now());
    final seconds = left.isNegative ? 0 : left.inSeconds;
    final mm = (seconds ~/ 60).toString();
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final messages = StoreLocalizations.of(context);
    final theme = Theme.of(context);
    final offer = _offer;
    final note = switch (_phase) {
      _Phase.expired => messages.codeExpired,
      _Phase.hidden => messages.codeHidden,
      _ => null,
    };
    return ZenPageScaffold(
      title: messages.addDeviceTitle,
      onBack: widget.onClose,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(messages.addDeviceIntro, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 24),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(note, style: theme.textTheme.bodyLarge),
              ),
            ),
          if (offer != null) ...[
            ZenPairingCodeView(qrData: offer.qrData, text: offer.text, showQr: widget.showQr),
            const SizedBox(height: 16),
            Text(
              messages.codeValidFor(_remaining(offer)),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ] else
            ZenButton(
              label: _phase == _Phase.idle ? messages.showCodeButton : messages.showNewCodeButton,
              onPressed: _show,
            ),
          const SizedBox(height: 24),
          ZenButton(
            label: messages.cancelButton,
            variant: ZenButtonVariant.text,
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }
}

DateTime _systemNow() => DateTime.now();
