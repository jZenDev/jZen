import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/zen_button.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing, ZenProgressIndicator;

import '../support/a11y.dart';

typedef Build =
    Widget Function(
      BuildContext context,
      String label,
      VoidCallback? onPressed,
      ZenButtonVariant variant,
      IconData? icon,
      bool isLoading,
    );

/// Both idioms are built directly: the public widget chooses one on a compile-time constant, so
/// one run only reaches the branch of the host it was compiled for.
final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialButton,
  'cupertino': buildCupertinoButton,
};

Widget wrap(
  Build build,
  ZenButtonVariant variant, {
  VoidCallback? onPressed,
  bool isLoading = false,
  IconData? icon,
  String label = 'Save',
}) => Builder(
  builder: (BuildContext context) => FocusRing.wrapping(
    child: build(context, label, isLoading ? null : onPressed, variant, icon, isLoading),
  ),
);

void main() {
  for (final MapEntry<String, Build> entry in builds.entries) {
    for (final ZenButtonVariant variant in ZenButtonVariant.values) {
      group('${entry.key} ${variant.name}', () {
        testWidgets('is one control, named by its label once, and taps', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          int taps = 0;
          await pumpApp(tester, wrap(entry.value, variant, onPressed: () => taps++));

          final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.tap);
          expect(nodes, hasLength(1), reason: nodes.map((n) => n.label).join(' | '));
          expect(nodes.single.label, 'Save');
          expect(nodes.single.flagsCollection.isButton, isTrue);
          expect(isEnabled(nodes.single), isTrue);

          await tester.tap(find.text('Save'));
          expect(taps, 1);
          handle.dispose();
        });

        testWidgets('Tab reaches it, Enter and Space activate it, and a ring shows', (
          tester,
        ) async {
          int taps = 0;
          await pumpApp(tester, wrap(entry.value, variant, onPressed: () => taps++));
          final Finder button = find.byType(FocusRing);
          expect(isRinged(tester, button), isFalse);

          await press(tester, LogicalKeyboardKey.tab);
          expect(isRinged(tester, button), isTrue);

          await press(tester, LogicalKeyboardKey.enter);
          expect(taps, 1);
          await press(tester, LogicalKeyboardKey.space);
          expect(taps, 2);
        }, semanticsEnabled: false);

        testWidgets('a pointer press hides the ring', (tester) async {
          await pumpApp(tester, wrap(entry.value, variant, onPressed: () {}));
          await press(tester, LogicalKeyboardKey.tab);
          expect(isRinged(tester, find.byType(FocusRing)), isTrue);

          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(isRinged(tester, find.byType(FocusRing)), isFalse);
        }, semanticsEnabled: false);

        testWidgets('disabled: announced as disabled, not tappable, not focusable', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpApp(tester, wrap(entry.value, variant));

          expect(nodesWith(tester, SemanticsAction.tap), isEmpty);
          final SemanticsNode node = tester.getSemantics(find.text('Save'));
          expect(node.label, contains('Save'));
          expect(isEnabled(node.getSemanticsData()), isFalse);
          handle.dispose();
        });

        testWidgets('loading keeps its name, is disabled, and adds no words', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpApp(
            tester,
            wrap(entry.value, variant, isLoading: true, onPressed: () {}),
            settle: false,
          );

          expect(find.byType(ZenProgressIndicator), findsOneWidget);
          final SemanticsNode node = tester.getSemantics(find.text('Save'));
          expect(node.label, 'Save');
          expect(isEnabled(node.getSemanticsData()), isFalse);
          handle.dispose();
        });

        testWidgets('an icon is decorative', (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpApp(tester, wrap(entry.value, variant, icon: Icons.save, onPressed: () {}));
          expect(tester.getSemantics(find.text('Save')).label, 'Save');
          handle.dispose();
        });

        testWidgets('reflows at 200% text on a narrow screen', (tester) async {
          await pumpApp(
            tester,
            wrap(entry.value, variant, onPressed: () {}, label: 'Save the reconciliation'),
            size: const Size(260, 700),
            textScale: 2,
          );
          expect(tester.takeException(), isNull);
        });

        for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
          testWidgets('meets AA text contrast (${theme.key})', (tester) async {
            final SemanticsHandle handle = tester.ensureSemantics();
            await pumpApp(tester, wrap(entry.value, variant, onPressed: () {}), theme: theme.value);
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            handle.dispose();
          });
        }
      });
    }
  }
}
