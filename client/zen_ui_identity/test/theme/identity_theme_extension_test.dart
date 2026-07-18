import 'package:zen_ui_identity/src/theme/identity_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fallback has expected defaults and copyWith/lerp work', () {
    final a = IdentityThemeExtension.fallback();
    final b = a.copyWith(brandColor: Colors.pink, spacing: 8.0);

    expect(b.brandColor, Colors.pink);
    expect(b.spacing, 8.0);

    final lerp = a.lerp(b, 0.5);
    expect(lerp.brandColor, isNotNull);
    expect(lerp.spacing, closeTo((a.spacing + b.spacing) / 2, 1e-9));
  });
}
