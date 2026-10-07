import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/zen_cupertino_text_form_field.dart';
import 'package:zen_ui_widgets/src/zen_text_field.dart';

import '../support/a11y.dart';

typedef Build = Widget Function(BuildContext context, ZenTextField field);

final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialTextField,
  'cupertino': buildCupertinoTextField,
};

/// A [ZenTextField]'s own build picks the host's idiom; this renders [entry]'s instead.
Widget field(
  Build build, {
  TextEditingController? controller,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  FormFieldValidator<String>? validator,
  AutovalidateMode autovalidateMode = AutovalidateMode.disabled,
  String? errorText,
  String? hint,
  bool obscureText = false,
  bool enabled = true,
  TextCapitalization capitalization = TextCapitalization.none,
  int? maxLines = 1,
  int? minLines,
  int? maxLength,
}) => Builder(
  builder: (BuildContext context) => build(
    context,
    ZenTextField(
      label: 'Email',
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      validator: validator,
      autovalidateMode: autovalidateMode,
      errorText: errorText,
      hint: hint,
      obscureText: obscureText,
      enabled: enabled,
      textCapitalization: capitalization,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
    ),
  ),
);

void main() {
  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('the label is the name of the focusable input, said once', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, field(entry.value));

        final SemanticsNode node = tester.getSemantics(find.byType(EditableText));
        expect(node.flagsCollection.isTextField, isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.focus), isTrue);
        expect(occurrences(node.label, 'Email'), 1, reason: node.label);
        expect(nodesWith(tester, SemanticsAction.focus), hasLength(1));
        handle.dispose();
      });

      testWidgets('typing reports the text and fills the controller', (tester) async {
        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);
        final List<String> seen = <String>[];
        await pumpApp(tester, field(entry.value, controller: controller, onChanged: seen.add));

        await tester.enterText(find.byType(EditableText), 'a@b.c');
        expect(seen, <String>['a@b.c']);
        expect(controller.text, 'a@b.c');
      });

      testWidgets('capitalization is passed to the keyboard', (tester) async {
        await pumpApp(tester, field(entry.value, capitalization: TextCapitalization.sentences));
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).textCapitalization,
          TextCapitalization.sentences,
        );
      });

      testWidgets('minLines and maxLines make a note that grows, then scrolls', (tester) async {
        await pumpApp(tester, field(entry.value, minLines: 3, maxLines: 6));
        final EditableText text = tester.widget<EditableText>(find.byType(EditableText));
        expect(text.minLines, 3);
        expect(text.maxLines, 6);

        final double empty = tester.getSize(find.byType(EditableText)).height;
        await tester.enterText(find.byType(EditableText), List.filled(12, 'line').join('\n'));
        await tester.pump();
        expect(tester.getSize(find.byType(EditableText)).height, greaterThan(empty));
      });

      testWidgets('a single line stays one line', (tester) async {
        await pumpApp(tester, field(entry.value));
        expect(tester.widget<EditableText>(find.byType(EditableText)).maxLines, 1);
      });

      testWidgets('maxLength refuses the extra characters and shows a counter', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpApp(tester, field(entry.value, controller: controller, maxLength: 5));
        expect(find.text('0/5'), findsOneWidget);

        await tester.enterText(find.byType(EditableText), 'abcdefgh');
        await tester.pump();
        expect(controller.text, 'abcde');
        expect(find.text('5/5'), findsOneWidget);
        // The counter is not a second focusable node beside the input.
        expect(nodesWith(tester, SemanticsAction.focus), hasLength(1));
        handle.dispose();
      });

      testWidgets('without maxLength there is no counter', (tester) async {
        await pumpApp(tester, field(entry.value));
        expect(find.textContaining(RegExp(r'^\d+/\d+$')), findsNothing);
      });

      testWidgets('the keyboard action key submits the text', (tester) async {
        final List<String> submitted = <String>[];
        await pumpApp(tester, field(entry.value, onSubmitted: submitted.add));

        await tester.enterText(find.byType(EditableText), 'a@b.c');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        expect(submitted, <String>['a@b.c']);
      });

      testWidgets('a hint shows while empty, and obscureText hides the text', (tester) async {
        await pumpApp(tester, field(entry.value, hint: 'you@example.com', obscureText: true));
        expect(find.text('you@example.com'), findsOneWidget);
        expect(tester.widget<EditableText>(find.byType(EditableText)).obscureText, isTrue);
      });

      testWidgets('a Form runs the validator, and the error is shown and read with the field', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final GlobalKey<FormState> form = GlobalKey<FormState>();
        await pumpApp(
          tester,
          Form(
            key: form,
            child: field(entry.value, validator: (String? v) => v!.isEmpty ? 'Required' : null),
          ),
        );

        expect(form.currentState!.validate(), isFalse);
        await tester.pumpAndSettle();
        expect(find.text('Required'), findsOneWidget);
        final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.focus);
        expect(
          nodes.single.label,
          contains('Required'),
          reason: 'the error is not on its own node',
        );

        await tester.enterText(find.byType(EditableText), 'x');
        expect(form.currentState!.validate(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Required'), findsNothing);
        handle.dispose();
      });

      testWidgets('validates as the user interacts when asked to', (tester) async {
        await pumpApp(
          tester,
          Form(
            child: field(
              entry.value,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (String? v) => v == 'bad' ? 'Not that one' : null,
            ),
          ),
        );
        expect(find.text('Not that one'), findsNothing);
        await tester.enterText(find.byType(EditableText), 'bad');
        await tester.pumpAndSettle();
        expect(find.text('Not that one'), findsOneWidget);
      });

      testWidgets('an app-decided error is shown and fails validation', (tester) async {
        final GlobalKey<FormState> form = GlobalKey<FormState>();
        await pumpApp(
          tester,
          Form(
            key: form,
            child: field(entry.value, errorText: 'Already taken'),
          ),
        );
        expect(find.text('Already taken'), findsOneWidget);
        expect(form.currentState!.validate(), isFalse);
      });

      testWidgets('an edit made to the controller is what the form validates', (tester) async {
        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);
        final GlobalKey<FormState> form = GlobalKey<FormState>();
        await pumpApp(
          tester,
          Form(
            key: form,
            child: field(
              entry.value,
              controller: controller,
              validator: (String? v) => v == 'ok' ? null : 'Wrong',
            ),
          ),
        );

        controller.text = 'ok';
        expect(form.currentState!.validate(), isTrue);
        controller.clear();
        expect(form.currentState!.validate(), isFalse);
      });

      testWidgets('a disabled field takes no input and says so', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, field(entry.value, enabled: false));
        expect(tester.widget<EditableText>(find.byType(EditableText)).readOnly, isTrue);
        expect(
          isEnabled(tester.getSemantics(find.byType(EditableText)).getSemanticsData()),
          isFalse,
        );
        handle.dispose();
      });

      testWidgets('Tab reaches it', (tester) async {
        await pumpApp(tester, field(entry.value));
        await press(tester, LogicalKeyboardKey.tab);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<EditableText>(),
          isNotNull,
        );
      }, semanticsEnabled: false);

      testWidgets('reflows at 200% text on a narrow screen', (tester) async {
        await pumpApp(
          tester,
          field(entry.value, errorText: 'Enter a valid email address'),
          size: const Size(260, 700),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA text contrast, error and hint included (${theme.key})', (
          tester,
        ) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpApp(
            tester,
            field(entry.value, errorText: 'Already taken', hint: 'you@example.com'),
            theme: theme.value,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    });
  }

  group('cupertino', () {
    testWidgets('draws a Cupertino field, not a Material one', (tester) async {
      await pumpApp(tester, field(buildCupertinoTextField));
      expect(find.byType(CupertinoTextField), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the focused field shows the focus ring', (tester) async {
      await pumpApp(tester, field(buildCupertinoTextField));
      await press(tester, LogicalKeyboardKey.tab);
      expect(isRinged(tester, find.byType(ZenCupertinoTextFormField)), isTrue);
    }, semanticsEnabled: false);

    testWidgets('reset restores the initial text and reports it', (tester) async {
      final GlobalKey<FormState> form = GlobalKey<FormState>();
      final List<String> seen = <String>[];
      await pumpApp(
        tester,
        Form(
          key: form,
          child: field(buildCupertinoTextField, onChanged: seen.add),
        ),
      );
      await tester.enterText(find.byType(EditableText), 'abc');
      form.currentState!.reset();
      await tester.pump();
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, '');
      expect(seen.last, '');
    });

    testWidgets('swapping the controller keeps the text', (tester) async {
      final TextEditingController one = TextEditingController(text: 'one');
      final TextEditingController two = TextEditingController(text: 'two');
      addTearDown(one.dispose);
      addTearDown(two.dispose);
      await pumpApp(tester, field(buildCupertinoTextField, controller: one));
      expect(find.text('one'), findsOneWidget);
      await pumpApp(tester, field(buildCupertinoTextField, controller: two));
      expect(find.text('two'), findsOneWidget);
      await pumpApp(tester, field(buildCupertinoTextField));
      expect(find.text('two'), findsOneWidget, reason: 'dropping the controller keeps the text');
    });
  });

  group('material', () {
    testWidgets('draws a Material field, not a Cupertino one', (tester) async {
      await pumpApp(tester, field(buildMaterialTextField));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(CupertinoTextField), findsNothing);
    });
  });
}
