import 'package:flutter/material.dart';

import '../theme/identity_theme_extension.dart';

enum IdentityButtonVariant { primary, secondary, text }

/// A reusable button for Identity flows.
class IdentityButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IdentityButtonVariant variant;
  final IconData? icon;

  const IdentityButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.variant = IdentityButtonVariant.primary,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ??
        IdentityThemeExtension.fallback();

    final disabled = onPressed == null || isLoading;

    return SizedBox(height: 48, child: _buildButton(context, theme, disabled));
  }

  Widget _buildButton(
    BuildContext context,
    IdentityThemeExtension theme,
    bool disabled,
  ) {
    final child = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: variant == IdentityButtonVariant.primary
                  ? theme.surfaceColor
                  : theme.brandColor,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          );

    switch (variant) {
      case IdentityButtonVariant.primary:
        return FilledButton(
          onPressed: disabled ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: theme.brandColor,
            foregroundColor: theme.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: child,
        );
      case IdentityButtonVariant.secondary:
        return OutlinedButton(
          onPressed: disabled ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.brandColor,
            side: BorderSide(color: theme.brandColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: child,
        );
      case IdentityButtonVariant.text:
        return TextButton(
          onPressed: disabled ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: theme.brandColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: child,
        );
    }
  }
}
