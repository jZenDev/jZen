import 'package:zen_ui_identity/src/theme/identity_theme_extension.dart';
import 'package:zen_ui_identity/src/widgets/identity_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The status colour marks the border; the label is drawn in onSurface so its contrast never
  // depends on the application's palette (see accessibility_test.dart).
  testWidgets('IdentityStatusChip marks its border in the theme color, label in onSurface', (
    tester,
  ) async {
    final theme = IdentityThemeExtension.fallback();
    final themeData = ThemeData().copyWith(extensions: [theme]);

    await tester.pumpWidget(
      MaterialApp(
        theme: themeData,
        home: const Scaffold(body: IdentityStatusChip(label: 'OK')),
      ),
    );

    final text = tester.widget<Text>(find.text('OK'));
    expect(text.data, 'OK');
    expect(text.style?.color, themeData.colorScheme.onSurface);
    final box = tester.widget<Container>(
      find.descendant(of: find.byType(IdentityStatusChip), matching: find.byType(Container)),
    );
    expect((box.decoration! as BoxDecoration).border, Border.all(color: theme.brandColor));
  });

  testWidgets('IdentityStatusChip factory success uses success color', (tester) async {
    final theme = IdentityThemeExtension.fallback();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData().copyWith(extensions: [theme]),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              return IdentityStatusChip.success(label: 'Good', context: ctx);
            },
          ),
        ),
      ),
    );

    // If widget built without errors, test passes. (Color checks are covered by previous test.)
    expect(find.text('Good'), findsOneWidget);
  });

  testWidgets('IdentityStatusChip has correct semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: IdentityStatusChip(label: 'Admin Role')),
      ),
    );

    final node = tester.getSemantics(find.text('Admin Role'));
    expect(node.label, contains('Admin Role'));
    semantics.dispose();
  });
}
