import 'package:flutter/material.dart';

import '../theme/identity_theme_extension.dart';

/// A chip to display status or role.
class IdentityStatusChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool isOutline;

  const IdentityStatusChip({
    super.key,
    required this.label,
    this.color,
    this.isOutline = false,
  });

  factory IdentityStatusChip.success({
    required String label,
    required BuildContext context,
  }) {
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ??
        IdentityThemeExtension.fallback();
    return IdentityStatusChip(label: label, color: theme.successColor);
  }

  factory IdentityStatusChip.warning({
    required String label,
    required BuildContext context,
  }) {
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ??
        IdentityThemeExtension.fallback();
    return IdentityStatusChip(label: label, color: theme.warningColor);
  }

  factory IdentityStatusChip.error({
    required String label,
    required BuildContext context,
  }) {
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ??
        IdentityThemeExtension.fallback();
    return IdentityStatusChip(label: label, color: theme.errorColor);
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ??
        IdentityThemeExtension.fallback();
    final effectiveColor = color ?? theme.brandColor;

    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isOutline
              ? Colors.transparent
              : effectiveColor.withValues(alpha: 0.1),
          border: Border.all(color: effectiveColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: effectiveColor,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
