import 'package:zen_ui_identity/src/theme/identity_theme_extension.dart';
import 'package:zen_ui_identity/src/widgets/identity_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show ZenButton, ZenProgressIndicator;

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
              IdentityButton(text: 'Text', onPressed: () {}, variant: IdentityButtonVariant.text),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Secondary'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
  });

  testWidgets('IdentityButton shows loading indicator when isLoading', (tester) async {
    final theme = IdentityThemeExtension.fallback();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData().copyWith(extensions: [theme]),
        home: const Scaffold(body: IdentityButton(text: 'Load', isLoading: true)),
      ),
    );

    expect(find.byType(ZenProgressIndicator), findsOneWidget);
  });

  testWidgets('IdentityButton is a ZenButton, so it follows the platform idiom', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdentityButton(text: 'Go', onPressed: () {}),
        ),
      ),
    );

    expect(find.byType(ZenButton), findsOneWidget);
    expect(find.byType(CupertinoButton), zenIsApplePlatform ? findsOneWidget : findsNothing);
    expect(find.byType(FilledButton), zenIsApplePlatform ? findsNothing : findsOneWidget);
  });

  testWidgets('IdentityButton hands the brand colour to the button', (tester) async {
    const brand = Color(0xFF123456);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData().copyWith(
          extensions: [IdentityThemeExtension.fallback().copyWith(brandColor: brand)],
        ),
        home: Scaffold(
          body: IdentityButton(text: 'Go', onPressed: () {}),
        ),
      ),
    );

    final scheme = Theme.of(tester.element(find.byType(ZenButton))).colorScheme;
    expect(scheme.primary, brand);
  });
}
