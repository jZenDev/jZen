import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../theme/identity_theme_extension.dart';

/// A reusable text field for Identity forms.
///
/// On Apple platforms this is a [ZenTextField], drawn Cupertino. Elsewhere it adapts to
/// [IdentityThemeExtension]: a filled field with the brand-colour border.
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
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (zenIsApplePlatform) {
      return ZenTextField(
        label: label,
        controller: controller,
        hint: hint,
        errorText: errorText,
        obscureText: obscureText,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        textInputAction: textInputAction,
        onSubmitted: onFieldSubmitted,
        validator: validator,
        enabled: enabled,
      );
    }

    // Access custom theme
    final theme =
        Theme.of(context).extension<IdentityThemeExtension>() ?? IdentityThemeExtension.fallback();

    final borderSide = BorderSide(color: theme.brandColor.withValues(alpha: 0.5));
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
        // Merged into the field's own node. Left as a separate Semantics, the label sat on a node
        // a screen reader never focuses, and the focusable field was named by its hint alone —
        // "you@example.com, text field", with no word of what the field is for.
        MergeSemantics(
          child: Semantics(
            label: label,
            child: TextFormField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              autofillHints: autofillHints,
              textInputAction: textInputAction,
              onFieldSubmitted: onFieldSubmitted,
              validator: validator,
              enabled: enabled,
              style: theme.subtitleStyle.copyWith(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: hint,
                errorText: errorText,
                filled: true,
                fillColor: theme.surfaceColor,
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
                  borderSide: borderSide.copyWith(width: 2, color: theme.brandColor),
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
        ),
      ],
    );
  }
}
