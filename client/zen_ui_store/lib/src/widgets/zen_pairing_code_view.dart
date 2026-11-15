import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/generated/store_localizations.dart';

/// A pairing code drawn twice: as a QR code for a camera, and as groups of characters for a
/// person to read and type.
///
/// The text is a plain [Text], not selectable, so a long press offers no Copy: the code is the
/// sync key, and the clipboard is shared with every other app and, on some systems, with the
/// person's other devices. The QR code is black on white whatever the theme, because a scanner
/// needs that contrast, not the app's.
class ZenPairingCodeView extends StatelessWidget {
  /// What the QR code carries.
  final String qrData;

  /// The typed form: groups separated by dashes.
  final String text;

  /// Whether to draw the QR code; a desktop with no phone to hand may still show it, so this is
  /// on unless the application has a reason.
  final bool showQr;

  const ZenPairingCodeView({
    super.key,
    required this.qrData,
    required this.text,
    this.showQr = true,
  });

  @override
  Widget build(BuildContext context) {
    final messages = StoreLocalizations.of(context);
    final theme = Theme.of(context);
    final groups = text.split('-');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showQr)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: qrData,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
              semanticsLabel: messages.qrCodeLabel,
            ),
          ),
        const SizedBox(height: 16),
        Semantics(
          container: true,
          label: messages.pairingCodeLabel,
          // Read group by group, each character on its own, not as one long unpronounceable word.
          value: groups.map((group) => group.split('').join(' ')).join(', '),
          child: ExcludeSemantics(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final group in groups)
                  Text(
                    group,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 1.5,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
