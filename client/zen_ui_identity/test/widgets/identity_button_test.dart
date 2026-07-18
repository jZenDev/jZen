import 'package:zen_ui_identity/src/theme/identity_theme_extension.dart';
import 'package:zen_ui_identity/src/widgets/identity_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('IdentityButton shows text and handles variants', (tester) async {
    final theme = IdentityThemeExtension.fallback();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData().copyWith(extensions: [theme]),
        home: Scaffold(
          body: Column(
            children: [
              IdentityButton(
                text: 'Primary',
                onPressed: () {},
                variant: IdentityButtonVariant.primary,
              ),
              IdentityButton(
                text: 'Secondary',
                onPressed: () {},
                variant: IdentityButtonVariant.secondary,
              ),
              IdentityButton(
                text: 'Text',
                onPressed: () {},
                variant: IdentityButtonVariant.text,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Secondary'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
  });

  testWidgets('IdentityButton shows loading indicator when isLoading', (
    tester,
  ) async {
    final theme = IdentityThemeExtension.fallback();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData().copyWith(extensions: [theme]),
        home: const Scaffold(
          body: IdentityButton(text: 'Load', isLoading: true),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
