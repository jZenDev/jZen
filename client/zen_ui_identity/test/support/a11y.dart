import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

/// WCAG 2.x contrast ratio between two opaque colours, 1.0 (none) to 21.0 (black on white).
double contrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The themes the identity widgets are audited under: the package's own fallback, and the shape a
/// jZen application supplies — a seeded Material 3 scheme — in light and dark. The seeded ones
/// deliberately keep the stock mid-tone `Colors.green` / `Colors.orange` for success and warning,
/// the palette an application most plausibly writes, which is under 3:1 as text on a light
/// surface; a widget must stay legible with it.
final Map<String, ThemeData> auditThemes = <String, ThemeData>{
  'fallback': ThemeData(extensions: [IdentityThemeExtension.fallback()]),
  for (final Brightness brightness in Brightness.values)
    'seeded ${brightness.name}': _seeded(brightness),
};

ThemeData _seeded(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    extensions: [
      IdentityThemeExtension(
        successColor: Colors.green,
        errorColor: scheme.error,
        warningColor: Colors.orange,
        brandColor: scheme.primary,
        surfaceColor: scheme.surface,
        titleStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        subtitleStyle: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
      ),
    ],
  );
}
