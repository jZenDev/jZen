import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import '../support/a11y.dart';

/// What a screen reader hears from the identity widgets, and whether their text is legible
/// (WCAG 1.4.3 Contrast, 4.1.2 Name, Role, Value).
void main() {
  group('IdentityTextField', () {
    testWidgets('the focusable field carries its label, not only its hint', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IdentityTextField(label: 'Email', hint: 'you@example.com'),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(EditableText));
      expect(node.flagsCollection.isTextField, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.focus), isTrue);
      expect(node.label, contains('Email'));
      expect(RegExp('Email').allMatches(node.label), hasLength(1), reason: node.label);
      handle.dispose();
    });
  });

  group('IdentityStatusChip', () {
    testWidgets('is one node that reads its label once', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: IdentityStatusChip(label: 'Admin Role')),
        ),
      );

      expect(tester.getSemantics(find.byType(IdentityStatusChip)).label, 'Admin Role');
      handle.dispose();
    });

    for (final entry in auditThemes.entries) {
      testWidgets('every variant meets AA text contrast (${entry.key})', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Wrap(
                  spacing: 8,
                  children: [
                    const IdentityStatusChip(label: 'brand'),
                    const IdentityStatusChip(label: 'outline', isOutline: true),
                    IdentityStatusChip.success(label: 'success', context: ctx),
                    IdentityStatusChip.warning(label: 'warning', context: ctx),
                    IdentityStatusChip.error(label: 'error', context: ctx),
                  ],
                ),
              ),
            ),
          ),
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('IdentityThemeExtension.fallback', () {
    // Each of these is drawn as text on the surface somewhere: brand as a button label and
    // title, status colours by applications, subtitle as body copy. 4.5:1 is WCAG AA for text.
    final theme = IdentityThemeExtension.fallback();
    final Map<String, Color> text = {
      'brand': theme.brandColor,
      'success': theme.successColor,
      'warning': theme.warningColor,
      'error': theme.errorColor,
      'subtitle': theme.subtitleStyle.color!,
    };
    for (final entry in text.entries) {
      test('${entry.key} meets 4.5:1 on the surface', () {
        expect(contrastRatio(entry.value, theme.surfaceColor), greaterThanOrEqualTo(4.5));
      });
    }
  });
}
