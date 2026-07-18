import 'package:zen_ui_identity/src/widgets/identity_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IdentityTextField', () {
    testWidgets('renders with label and controller', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdentityTextField(label: 'Email', controller: controller),
          ),
        ),
      );

      expect(find.text('Email'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('shows error text when provided', (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdentityTextField(
              label: 'Email',
              controller: controller,
              errorText: 'Invalid email',
            ),
          ),
        ),
      );

      expect(find.text('Invalid email'), findsOneWidget);
    });

    testWidgets('applies obscureText for password field', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdentityTextField(
              label: 'Password',
              controller: controller,
              obscureText: true,
            ),
          ),
        ),
      );

      // Widget renders without error
      expect(find.byType(IdentityTextField), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('updates controller when text changes', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdentityTextField(label: 'Email', controller: controller),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'test@example.com');
      await tester.pumpAndSettle();

      expect(controller.text, 'test@example.com');
    });

    testWidgets('applies custom keyboard type', (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdentityTextField(
              label: 'Email',
              controller: controller,
              keyboardType: TextInputType.emailAddress,
            ),
          ),
        ),
      );

      // Widget renders without error
      expect(find.byType(IdentityTextField), findsOneWidget);
    });
  });
}
