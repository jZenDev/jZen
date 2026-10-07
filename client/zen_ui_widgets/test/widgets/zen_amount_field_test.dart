import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../support/a11y.dart';

TextEditingValue edit(ZenAmountInputFormatter f, String from, String to) => f.formatEditUpdate(
  TextEditingValue(
    text: from,
    selection: TextSelection.collapsed(offset: from.length),
  ),
  TextEditingValue(
    text: to,
    selection: TextSelection.collapsed(offset: to.length),
  ),
);

/// The editable input of the field labelled [label], whichever idiom drew it.
Finder input(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(ZenTextField)),
  matching: find.byType(EditableText),
);

void main() {
  group('normalizeAmount', () {
    test('canonicalises either decimal mark, grouping and a missing whole part', () {
      expect(normalizeAmount('12.5'), '12.5');
      expect(normalizeAmount('12,5'), '12.5');
      expect(normalizeAmount('1 234,50'), '1234.50');
      expect(normalizeAmount('1 234.5'), '1234.5');
      expect(normalizeAmount('.5'), '0.5');
      expect(normalizeAmount('5.'), '5');
      expect(normalizeAmount('-3'), '-3');
      expect(normalizeAmount('007'), '007', reason: 'digits are the app\'s to interpret');
    });

    test('rejects what is not a number', () {
      for (final String bad in <String>[
        '',
        ' ',
        '-',
        '.',
        ',',
        'abc',
        '1.2.3',
        '1,2,3',
        '1e5',
        '--1',
        '1-',
      ]) {
        expect(normalizeAmount(bad), isNull, reason: '"$bad"');
      }
    });

    test('honours the sign and precision limits', () {
      expect(normalizeAmount('-1', allowNegative: false), isNull);
      expect(normalizeAmount('1.234', maxFractionDigits: 2), isNull);
      expect(normalizeAmount('1.23', maxFractionDigits: 2), '1.23');
      expect(normalizeAmount('1.5', maxFractionDigits: 0), isNull);
      expect(normalizeAmount('15', maxFractionDigits: 0), '15');
    });

    test('parseAmount is the same number as a double', () {
      expect(parseAmount('1 234,5'), 1234.5);
      expect(parseAmount('x'), isNull);
    });
  });

  test('the locale decides the separator', () {
    expect(zenDecimalSeparator(const Locale('en')), '.');
    expect(zenDecimalSeparator(const Locale('uk')), ',');
    expect(zenDecimalSeparator(const Locale('xx')), '.', reason: 'an unknown locale falls back');
  });

  group('ZenAmountInputFormatter', () {
    final ZenAmountInputFormatter en = ZenAmountInputFormatter(decimalSeparator: '.');
    final ZenAmountInputFormatter uk = ZenAmountInputFormatter(decimalSeparator: ',');

    test('accepts digits, one mark and a leading minus', () {
      expect(edit(en, '', '-').text, '-');
      expect(edit(en, '-', '-1').text, '-1');
      expect(edit(en, '1', '1.').text, '1.');
      expect(edit(en, '1.', '1.5').text, '1.5');
    });

    test('refuses letters, a second mark and a stray minus, keeping the old text', () {
      expect(edit(en, '1', '1a').text, '1');
      expect(edit(en, '1.5', '1.5.').text, '1.5');
      expect(edit(en, '1', '1-').text, '1');
      expect(edit(en, '1', '1e').text, '1');
    });

    test('writes the locale\'s own mark whichever one was typed', () {
      expect(edit(uk, '1', '1.').text, '1,');
      expect(edit(uk, '1', '1,').text, '1,');
      expect(edit(en, '1', '1,').text, '1.');
    });

    test('drops grouping spaces from pasted text', () {
      expect(edit(en, '', '1 234').text, '1234');
    });

    test('limits fractional digits, and forbids the mark at zero', () {
      final ZenAmountInputFormatter cents = ZenAmountInputFormatter(
        decimalSeparator: '.',
        maxFractionDigits: 2,
      );
      expect(edit(cents, '1.23', '1.234').text, '1.23');
      expect(edit(cents, '1.2', '1.23').text, '1.23');

      final ZenAmountInputFormatter whole = ZenAmountInputFormatter(
        decimalSeparator: '.',
        maxFractionDigits: 0,
      );
      expect(edit(whole, '1', '1.').text, '1');
    });

    test('refuses a minus when negatives are not allowed', () {
      final ZenAmountInputFormatter positive = ZenAmountInputFormatter(
        decimalSeparator: '.',
        allowNegative: false,
      );
      expect(edit(positive, '', '-').text, '');
    });
  });

  group('ZenAmountField', () {
    Widget field({
      TextEditingController? controller,
      ValueChanged<String?>? onChanged,
      int? maxFractionDigits,
      String? errorText,
      bool enabled = true,
    }) => ZenAmountField(
      label: 'Amount',
      controller: controller,
      onChanged: onChanged,
      maxFractionDigits: maxFractionDigits,
      errorText: errorText,
      enabled: enabled,
    );

    testWidgets('the label is the name of the focusable input itself', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, field());

      final SemanticsNode node = tester.getSemantics(find.byType(EditableText));
      expect(node.flagsCollection.isTextField, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.focus), isTrue);
      expect(node.label, contains('Amount'));
      expect(occurrences(node.label, 'Amount'), 1, reason: node.label);
      handle.dispose();
    });

    testWidgets('asks for a decimal keyboard with a sign, or a whole-number one', (tester) async {
      await pumpApp(tester, field());
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).keyboardType,
        const TextInputType.numberWithOptions(decimal: true, signed: true),
      );
      await pumpApp(tester, field(maxFractionDigits: 0));
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).keyboardType,
        const TextInputType.numberWithOptions(decimal: false, signed: true),
      );
    });

    testWidgets('reports canonical text as it is typed, null while it is not a number', (
      tester,
    ) async {
      final List<String?> seen = <String?>[];
      await pumpApp(tester, field(onChanged: seen.add));
      await tester.enterText(find.byType(EditableText), '12,5');
      await tester.enterText(find.byType(EditableText), '');
      await tester.enterText(find.byType(EditableText), '-');
      expect(seen, <String?>['12.5', null, null]);
    });

    testWidgets('the field writes the locale\'s mark, not the one typed', (tester) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpApp(tester, field(controller: controller), locale: const Locale('uk'));
      await tester.enterText(find.byType(EditableText), '12.5');
      expect(controller.text, '12,5');
    });

    testWidgets('an unusable value is called out in the locale, and read with the field', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final TextEditingController controller = TextEditingController(text: '-');
      addTearDown(controller.dispose);
      final GlobalKey<FormState> form = GlobalKey<FormState>();
      await pumpApp(
        tester,
        Form(
          key: form,
          child: field(controller: controller),
        ),
      );

      expect(form.currentState!.validate(), isFalse, reason: 'a Form sees it');
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid amount'), findsOneWidget);
      expect(
        nodesWith(tester, SemanticsAction.focus).single.label,
        contains('Enter a valid amount'),
      );
      handle.dispose();
    });

    testWidgets('speaks Ukrainian', (tester) async {
      final TextEditingController controller = TextEditingController(text: '-');
      addTearDown(controller.dispose);
      final GlobalKey<FormState> form = GlobalKey<FormState>();
      await pumpApp(
        tester,
        Form(
          key: form,
          child: field(controller: controller),
        ),
        locale: const Locale('uk'),
      );
      form.currentState!.validate();
      await tester.pumpAndSettle();
      expect(find.text('Введіть коректну суму'), findsOneWidget);
    });

    testWidgets('an empty field is valid: whether it is required is the form\'s call', (
      tester,
    ) async {
      final GlobalKey<FormState> form = GlobalKey<FormState>();
      await pumpApp(tester, Form(key: form, child: field()));
      expect(form.currentState!.validate(), isTrue);
    });

    testWidgets('an error the app decides on is shown and fails validation', (tester) async {
      final GlobalKey<FormState> form = GlobalKey<FormState>();
      await pumpApp(
        tester,
        Form(
          key: form,
          child: field(errorText: 'Exceeds balance'),
        ),
      );
      expect(find.text('Exceeds balance'), findsOneWidget);
      expect(form.currentState!.validate(), isFalse);
    });

    for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
      testWidgets('meets AA text contrast, error included (${theme.key})', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, field(errorText: 'Exceeds balance'), theme: theme.value);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('Tab reaches it and it shows a visible focus indicator', (tester) async {
      await pumpApp(tester, field());
      await press(tester, LogicalKeyboardKey.tab);
      expect(
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
      );
      if (find.byType(InputDecorator).evaluate().isNotEmpty) {
        // Material: the text field's own focused border, 2 px in the theme's primary colour.
        final InputDecorator decorator = tester.widget<InputDecorator>(find.byType(InputDecorator));
        expect(decorator.isFocused, isTrue);
      } else {
        // Cupertino: the shared focus ring.
        expect(isRinged(tester, find.byType(ZenTextField)), isTrue);
      }
    }, semanticsEnabled: false);
  });

  group('ZenAmountRangeField', () {
    late TextEditingController min;
    late TextEditingController max;

    setUp(() {
      min = TextEditingController();
      max = TextEditingController();
    });
    tearDown(() {
      min.dispose();
      max.dispose();
    });

    Widget range({void Function(String?, String?)? onChanged}) => ZenAmountRangeField(
      minLabel: 'Min',
      maxLabel: 'Max',
      minController: min,
      maxController: max,
      onChanged: onChanged,
    );

    testWidgets('a minimum above the maximum is called out under the maximum', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, range());
      await tester.enterText(input('Min'), '50');
      await tester.enterText(input('Max'), '10');
      await tester.pumpAndSettle();

      expect(find.text('The minimum must not be greater than the maximum'), findsOneWidget);
      expect(
        nodesWith(
          tester,
          SemanticsAction.focus,
        ).where((SemanticsData d) => d.label.startsWith('Max')).single.label,
        contains('must not be greater'),
      );
      handle.dispose();
    });

    testWidgets('fixing either end clears the error', (tester) async {
      await pumpApp(tester, range());
      await tester.enterText(input('Min'), '50');
      await tester.enterText(input('Max'), '10');
      await tester.pumpAndSettle();
      await tester.enterText(input('Min'), '5');
      await tester.pumpAndSettle();
      expect(find.textContaining('must not be greater'), findsNothing);
    });

    testWidgets('equal ends, one end, and none are all valid', (tester) async {
      await pumpApp(tester, range());
      await tester.enterText(input('Min'), '10');
      await tester.pumpAndSettle();
      expect(find.textContaining('must not be greater'), findsNothing);
      await tester.enterText(input('Max'), '10,0');
      await tester.pumpAndSettle();
      expect(find.textContaining('must not be greater'), findsNothing);
    });

    testWidgets('an inverted range fails an enclosing Form', (tester) async {
      final GlobalKey<FormState> form = GlobalKey<FormState>();
      await pumpApp(tester, Form(key: form, child: range()));
      await tester.enterText(input('Min'), '50');
      await tester.enterText(input('Max'), '10');
      await tester.pumpAndSettle();
      expect(form.currentState!.validate(), isFalse);
      await tester.enterText(input('Max'), '60');
      await tester.pumpAndSettle();
      expect(form.currentState!.validate(), isTrue);
    });

    testWidgets('reports both ends, canonical, on every change', (tester) async {
      final List<(String?, String?)> seen = <(String?, String?)>[];
      await pumpApp(tester, range(onChanged: (String? a, String? b) => seen.add((a, b))));
      await tester.enterText(input('Min'), '1,5');
      await tester.enterText(input('Max'), '9');
      expect(seen, <(String?, String?)>[('1.5', null), ('1.5', '9')]);
    });

    testWidgets('stacks the two fields at 200% text on a narrow screen', (tester) async {
      await pumpApp(tester, range(), size: const Size(320, 800), textScale: 2);
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(input('Max')).dy,
        greaterThan(tester.getBottomLeft(input('Min')).dy - 1),
      );
    });

    for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
      testWidgets('meets AA text contrast with the error showing (${theme.key})', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, range(), theme: theme.value);
        await tester.enterText(input('Min'), '50');
        await tester.enterText(input('Max'), '10');
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });
}
