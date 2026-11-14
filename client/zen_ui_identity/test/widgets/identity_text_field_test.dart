import 'package:zen_ui_identity/src/widgets/identity_text_field.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show ZenIconButton, zenWidgetsLocaleDelegate;

import '../support/localized_app.dart';

/// The reveal button by its name, which is its tooltip on Material and its semantics label on Apple.
Finder toggle(String label) =>
    find.byWidgetPredicate((widget) => widget is ZenIconButton && widget.label == label);

void main() {
  group('IdentityTextField', () {
    testWidgets('renders with label and controller', (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdentityTextField(label: 'Email', controller: controller),
          ),
        ),
      );

      expect(find.text('Email'), findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget);
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

    group('a password field', () {
      Future<TextEditingController> pump(WidgetTester tester, {bool enabled = true}) async {
        final controller = TextEditingController();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [zenWidgetsLocaleDelegate],
            home: Scaffold(
              body: IdentityTextField(
                label: 'Password',
                controller: controller,
                obscureText: true,
                enabled: enabled,
              ),
            ),
          ),
        );
        return controller;
      }

      bool obscured(WidgetTester tester) =>
          tester.widget<EditableText>(find.byType(EditableText)).obscureText;

      testWidgets('is hidden until the person reveals it, and hides again', (tester) async {
        await pump(tester);
        expect(obscured(tester), isTrue);

        await tester.tap(toggle('Show password'));
        await tester.pump();
        expect(obscured(tester), isFalse);
        expect(toggle('Show password'), findsNothing);

        await tester.tap(toggle('Hide password'));
        await tester.pump();
        expect(obscured(tester), isTrue);
      });

      testWidgets('keeps what was typed when it is revealed', (tester) async {
        final controller = await pump(tester);
        await tester.enterText(find.byType(EditableText), 's3cret');
        await tester.tap(toggle('Show password'));
        await tester.pump();
        expect(controller.text, 's3cret');
      });

      testWidgets('names the button, apart from the input, in the current state', (tester) async {
        final handle = tester.ensureSemantics();
        await pump(tester);

        expect(find.bySemanticsLabel('Show password'), findsOneWidget);
        final input = tester.getSemantics(find.byType(EditableText));
        expect(input.label, isNot(contains('Show password')));

        await tester.tap(toggle('Show password'));
        await tester.pump();
        expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
        expect(find.bySemanticsLabel('Show password'), findsNothing);
        handle.dispose();
      });

      testWidgets('speaks Ukrainian', (tester) async {
        await tester.pumpWidget(
          localizedApp(
            locale: 'uk',
            home: const Scaffold(body: IdentityTextField(label: 'Пароль', obscureText: true)),
          ),
        );
        expect(toggle('Показати пароль'), findsOneWidget);
      });

      testWidgets('cannot be revealed while the field is disabled', (tester) async {
        await pump(tester, enabled: false);
        await tester.tap(toggle('Show password'), warnIfMissed: false);
        await tester.pump();
        expect(obscured(tester), isTrue);
      });
    });

    testWidgets('a field that is not a password has no reveal button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: IdentityTextField(label: 'Email')),
        ),
      );
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('updates controller when text changes', (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdentityTextField(label: 'Email', controller: controller),
          ),
        ),
      );

      await tester.enterText(find.byType(EditableText), 'test@example.com');
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

    testWidgets('is Cupertino on Apple platforms and Material elsewhere', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: IdentityTextField(label: 'Email')),
        ),
      );

      expect(find.byType(CupertinoTextField), zenIsApplePlatform ? findsOneWidget : findsNothing);
      expect(find.byType(TextField), zenIsApplePlatform ? findsNothing : findsOneWidget);
    });
  });
}
