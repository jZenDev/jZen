import 'package:flutter/material.dart';

import '../theme/identity_theme_extension.dart';

/// A reusable text field for Identity forms.
///
/// Adapts to [IdentityThemeExtension].
class IdentityTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final Widget? suffixIcon;
  final bool enabled;

  const IdentityTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onFieldSubmitted,
    this.validator,
    this.suffixIcon,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // Access custom theme
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ??
        IdentityThemeExtension.fallback();

    final borderSide = BorderSide(
      color: theme.brandColor.withValues(alpha: 0.5),
    );
    final errorBorderSide = BorderSide(color: theme.errorColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: theme.subtitleStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        SizedBox(height: theme.spacing / 2),
        Semantics(
          label: label,
          textField: true,
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            autofillHints: autofillHints,
            textInputAction: textInputAction,
            onFieldSubmitted: onFieldSubmitted,
            validator: validator,
            enabled: enabled,
            style: theme.subtitleStyle.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: hint,
              errorText: errorText,
              filled: true,
              fillColor: theme.surfaceColor,
              suffixIcon: suffixIcon,
              contentPadding: EdgeInsets.symmetric(
                horizontal: theme.spacing,
                vertical: theme.spacing,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: borderSide,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: borderSide,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: borderSide.copyWith(
                  width: 2,
                  color: theme.brandColor,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: errorBorderSide,
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: errorBorderSide.copyWith(width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
