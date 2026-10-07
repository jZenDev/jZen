import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../theme/identity_theme_extension.dart';

enum IdentityButtonVariant { primary, secondary, text }

/// A reusable button for Identity flows.
///
/// A [ZenButton] underneath, so it is Cupertino on Apple platforms and Material elsewhere, and
/// announces its label once, including while [isLoading]. The identity theme's brand colour is
/// handed to it as the colour scheme's primary, so it keeps the application's brand.
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
        Theme.of(context).extension<IdentityThemeExtension>() ?? IdentityThemeExtension.fallback();
    final base = Theme.of(context);

    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: theme.brandColor,
          onPrimary: theme.surfaceColor,
          outline: theme.brandColor,
        ),
      ),
      child: ZenButton(
        label: text,
        onPressed: onPressed,
        isLoading: isLoading,
        icon: icon,
        variant: switch (variant) {
          IdentityButtonVariant.primary => ZenButtonVariant.primary,
          IdentityButtonVariant.secondary => ZenButtonVariant.secondary,
          IdentityButtonVariant.text => ZenButtonVariant.text,
        },
      ),
    );
  }
}
