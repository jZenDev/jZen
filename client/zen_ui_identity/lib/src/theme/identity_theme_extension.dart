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

  /// fallback factory
  factory IdentityThemeExtension.fallback() => const IdentityThemeExtension(
    successColor: Colors.green,
    errorColor: Colors.red,
    warningColor: Colors.orange,
    brandColor: Colors.blue,
    surfaceColor: Colors.white,
    titleStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    subtitleStyle: TextStyle(fontSize: 14, color: Colors.grey),
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
  IdentityThemeExtension lerp(
    covariant ThemeExtension<IdentityThemeExtension>? other,
    double t,
  ) {
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
      containerPadding: EdgeInsetsGeometry.lerp(
        containerPadding,
        other.containerPadding,
        t,
      )!,
      spacing: (spacing + (other.spacing - spacing) * t),
    );
  }
}
