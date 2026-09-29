import 'package:flutter/material.dart';

/// Theme extension for jZen identity UI components.
///
/// Allows configuring colors, text styles, and other visual properties
/// specific to authentication and profile screens.
class IdentityThemeExtension extends ThemeExtension<IdentityThemeExtension> {
  /// Color for success states (e.g. verified email).
  final Color successColor;

  /// Color for error states (e.g. login failed).
  final Color errorColor;

  /// Color for warning states (e.g. weak password).
  final Color warningColor;

  /// Color for usage in headers or primary actions if different from app primary.
  final Color brandColor;

  /// Background color for cards/containers.
  final Color surfaceColor;

  /// Text style for titles.
  final TextStyle titleStyle;

  /// Text style for subtitles/captions.
  final TextStyle subtitleStyle;

  /// Padding for standard containers.
  final EdgeInsetsGeometry containerPadding;

  /// Spacing between elements.
  final double spacing;

  const IdentityThemeExtension({
    required this.successColor,
    required this.errorColor,
    required this.warningColor,
    required this.brandColor,
    required this.surfaceColor,
    required this.titleStyle,
    required this.subtitleStyle,
    this.containerPadding = const EdgeInsets.all(24.0),
    this.spacing = 16.0,
  });

  /// The palette used when an application registers no extension of its own.
  ///
  /// Every colour here is drawn as text on [surfaceColor] somewhere — the brand colour as a
  /// button label and title, the subtitle colour as body copy — so each clears the 4.5:1 WCAG AA
  /// text contrast against white. The Material 500 shades this used to use do not: they measured
  /// between 2.2:1 (orange) and 3.7:1 (red). The shades below all clear 5:1, so the 10% tint a
  /// status chip lays under them does not pull any of them back under the line.
  factory IdentityThemeExtension.fallback() => const IdentityThemeExtension(
    successColor: Color(0xFF2E7D32), // Colors.green.shade800, 5.1:1 on white
    errorColor: Color(0xFFC62828), // Colors.red.shade800, 5.6:1
    warningColor: Color(0xFFB45309), // amber; no Material orange reaches 4.5:1 on white, 5.0:1
    brandColor: Color(0xFF1565C0), // Colors.blue.shade800, 5.8:1
    surfaceColor: Colors.white,
    titleStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    subtitleStyle: TextStyle(fontSize: 14, color: Color(0xFF616161)), // grey.shade700, 6.2:1
  );

  @override
  IdentityThemeExtension copyWith({
    Color? successColor,
    Color? errorColor,
    Color? warningColor,
    Color? brandColor,
    Color? surfaceColor,
    TextStyle? titleStyle,
    TextStyle? subtitleStyle,
    EdgeInsetsGeometry? containerPadding,
    double? spacing,
  }) {
    return IdentityThemeExtension(
      successColor: successColor ?? this.successColor,
      errorColor: errorColor ?? this.errorColor,
      warningColor: warningColor ?? this.warningColor,
      brandColor: brandColor ?? this.brandColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      titleStyle: titleStyle ?? this.titleStyle,
      subtitleStyle: subtitleStyle ?? this.subtitleStyle,
      containerPadding: containerPadding ?? this.containerPadding,
      spacing: spacing ?? this.spacing,
    );
  }

  @override
  IdentityThemeExtension lerp(covariant ThemeExtension<IdentityThemeExtension>? other, double t) {
    if (other is! IdentityThemeExtension) {
      return this;
    }
    return IdentityThemeExtension(
      successColor: Color.lerp(successColor, other.successColor, t)!,
      errorColor: Color.lerp(errorColor, other.errorColor, t)!,
      warningColor: Color.lerp(warningColor, other.warningColor, t)!,
      brandColor: Color.lerp(brandColor, other.brandColor, t)!,
      surfaceColor: Color.lerp(surfaceColor, other.surfaceColor, t)!,
      titleStyle: TextStyle.lerp(titleStyle, other.titleStyle, t)!,
      subtitleStyle: TextStyle.lerp(subtitleStyle, other.subtitleStyle, t)!,
      containerPadding: EdgeInsetsGeometry.lerp(containerPadding, other.containerPadding, t)!,
      spacing: (spacing + (other.spacing - spacing) * t),
    );
  }
}
