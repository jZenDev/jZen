import 'package:flutter/material.dart';

import '../theme/identity_theme_extension.dart';

/// A chip to display status or role.
class IdentityStatusChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool isOutline;

  const IdentityStatusChip({super.key, required this.label, this.color, this.isOutline = false});

  factory IdentityStatusChip.success({required String label, required BuildContext context}) {
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ?? IdentityThemeExtension.fallback();
    return IdentityStatusChip(label: label, color: theme.successColor);
  }

  factory IdentityStatusChip.warning({required String label, required BuildContext context}) {
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ?? IdentityThemeExtension.fallback();
    return IdentityStatusChip(label: label, color: theme.warningColor);
  }

  factory IdentityStatusChip.error({required String label, required BuildContext context}) {
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ?? IdentityThemeExtension.fallback();
    return IdentityStatusChip(label: label, color: theme.errorColor);
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ?? IdentityThemeExtension.fallback();
    final effectiveColor = color ?? theme.brandColor;

    // One node, read once. Semantics(label) around a Text announced the label twice.
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isOutline ? Colors.transparent : effectiveColor.withValues(alpha: 0.1),
          border: Border.all(color: effectiveColor),
          borderRadius: BorderRadius.circular(16),
        ),
        // The status colour marks the border and tint; the label is drawn in onSurface. The
        // colour is the application's, and a status colour that reads well as a border (a
        // mid-tone green or orange) is routinely under the 4.5:1 WCAG AA asks of 12px text — so
        // colouring the text made its legibility depend on a palette this widget cannot check.
        // The label, not the colour, is what says which status it is (SC 1.4.1).
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
