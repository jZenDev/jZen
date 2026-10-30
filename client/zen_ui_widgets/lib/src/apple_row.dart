import 'package:flutter/material.dart';

import 'adaptive_ink_well.dart';

/// The row an Apple-idiom selection control (checkbox, radio) is drawn in: [control] and a text
/// column of [label] and an optional [subtitle], the whole row one ink-free tap target.
///
/// The row only lays out and activates. The caller wraps it in the semantics node that names the
/// control and decides what takes focus, so the glyph inside — which is a real Cupertino widget
/// with semantics of its own — is not announced a second time.
Widget buildAppleRow(
  BuildContext context, {
  required String label,
  required Widget control,
  required VoidCallback? onTap,
  String? subtitle,
  bool focusable = true,
}) {
  final ThemeData theme = Theme.of(context);
  final TextStyle? subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );
  return buildCupertinoInkWell(
    onTap: onTap,
    canRequestFocus: focusable,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            control,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: theme.textTheme.bodyLarge),
                  if (subtitle != null) Text(subtitle, style: subtitleStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
