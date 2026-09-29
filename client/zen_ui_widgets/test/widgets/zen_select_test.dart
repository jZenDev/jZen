import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/zen_select.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../support/a11y.dart';

const List<String> currencies = <String>['EUR', 'UAH', 'USD'];

typedef Build = Widget Function(BuildContext context, ZenSelect<String> select);

final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialSelect<String>,
  'cupertino': buildCupertinoSelect<String>,
};

/// A select whose value the test owns, as an app's would be.
class Host extends StatefulWidget {
  const Host({required this.build, this.initial, this.errorText, this.enabled = true, super.key});

  final Build build;
  final String? initial;
  final String? errorText;
  final bool enabled;

  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  String? value;

  @override
  void initState() {
    super.initState();
    value = widget.initial;
  }

  @override
  Widget build(BuildContext context) => widget.build(
    context,
    ZenSelect<String>(
      label: 'Currency',
      hint: 'Choose one',
      items: currencies,
      itemLabel: (String c) => 'Currency $c',
      value: value,
      errorText: widget.errorText,
      onChanged: widget.enabled ? (String c) => setState(() => value = c) : null,
    ),
  );
}

void main() {
  group('material', () {
    testWidgets('is one control named by its label and value, and opens on tap', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, const Host(build: buildMaterialSelect, initial: 'UAH'));

      final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.tap);
      expect(nodes, hasLength(1), reason: nodes.map((n) => n.label).join(' | '));
      expect(nodes.single.label, contains('Currency'));
      expect(nodes.single.label, contains('UAH'));
      expect(occurrences(nodes.single.label, 'Currency\n'), lessThanOrEqualTo(1));
      expect(nodes.single.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('choosing an item reports it and shows it', (tester) async {
      await pumpApp(tester, const Host(build: buildMaterialSelect, initial: 'EUR'));
      await tester.tap(find.text('Currency EUR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Currency USD').last);
      await tester.pumpAndSettle();
      expect(find.text('Currency USD'), findsOneWidget);
    });

    testWidgets('the keyboard opens it and chooses, and a ring shows', (tester) async {
      await pumpApp(tester, const Host(build: buildMaterialSelect, initial: 'EUR'));
      await press(tester, LogicalKeyboardKey.tab);
      expect(isRinged(tester, find.byType(FocusRing)), isTrue);
      await press(tester, LogicalKeyboardKey.enter);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.text('Currency UAH'), findsOneWidget);
    }, semanticsEnabled: false);

    testWidgets('shows its hint while empty and its error text, and reads the error', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, const Host(build: buildMaterialSelect, errorText: 'Pick a currency'));
      expect(find.text('Pick a currency'), findsOneWidget);
      final SemanticsData node = nodesWith(tester, SemanticsAction.tap).single;
      expect(node.label, contains('Pick a currency'));
      handle.dispose();
    });

    testWidgets('disabled: no tap action', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, const Host(build: buildMaterialSelect, initial: 'EUR', enabled: false));
      expect(nodesWith(tester, SemanticsAction.tap), isEmpty);
      handle.dispose();
    });
  });

  group('cupertino wheel', () {
    testWidgets('is one control named by label and value', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, const Host(build: buildCupertinoSelect, initial: 'UAH'));
      final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.tap);
      expect(nodes, hasLength(1), reason: nodes.map((n) => n.label).join(' | '));
      expect(nodes.single.label, contains('Currency'));
      expect(nodes.single.label, contains('UAH'));
      handle.dispose();
    });

    testWidgets('Done commits the wheel, dismissing does not', (tester) async {
      await pumpApp(tester, const Host(build: buildCupertinoSelect, initial: 'EUR'));

      await tester.tap(find.text('Currency EUR'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsOneWidget);
      await tester.drag(find.byType(CupertinoPicker), const Offset(0, -80));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // the barrier
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsNothing);
      expect(find.text('Currency EUR'), findsOneWidget, reason: 'dismissed: nothing committed');

      await tester.tap(find.text('Currency EUR'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CupertinoPicker), const Offset(0, -80));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Currency EUR'), findsNothing);
    });

    testWidgets('Tab reaches it and Enter opens the wheel', (tester) async {
      await pumpApp(tester, const Host(build: buildCupertinoSelect, initial: 'EUR'));
      await press(tester, LogicalKeyboardKey.tab);
      expect(isRinged(tester, find.byType(FocusRing)), isTrue);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(CupertinoPicker), findsOneWidget);
    }, semanticsEnabled: false);
  });

  for (final MapEntry<String, Build> entry in builds.entries) {
    for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
      testWidgets('${entry.key} meets AA text contrast (${theme.key})', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(
          tester,
          Host(build: entry.value, initial: 'EUR', errorText: 'Pick a currency'),
          theme: theme.value,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }

  testWidgets('field border stands 3:1 off the surface in every theme (SC 1.4.11)', (tester) async {
    for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
      final ColorScheme scheme = theme.value.colorScheme;
      expect(
        contrastRatio(scheme.outline, scheme.surface),
        greaterThanOrEqualTo(3),
        reason: theme.key,
      );
    }
  });
}
