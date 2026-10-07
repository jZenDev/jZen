import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/zen_icon_button.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../support/a11y.dart';

typedef Build =
    Widget Function(BuildContext context, IconData icon, String label, VoidCallback? onPressed);

/// Both idioms are built directly: the public widget chooses one on a compile-time constant, so
/// one run only reaches the branch of the host it was compiled for.
final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialIconButton,
  'cupertino': buildCupertinoIconButton,
};

Widget wrap(Build build, {VoidCallback? onPressed}) => Builder(
  builder: (BuildContext context) =>
      FocusRing.wrapping(child: build(context, Icons.logout, 'Log out', onPressed)),
);

void main() {
  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('is one control, named by its label once, and taps', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        int taps = 0;
        await pumpApp(tester, wrap(entry.value, onPressed: () => taps++));

        final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.tap);
        expect(nodes, hasLength(1), reason: nodes.map((n) => n.label).join(' | '));
        expect(nodes.single.label, 'Log out');
        expect(nodes.single.flagsCollection.isButton, isTrue);
        expect(isEnabled(nodes.single), isTrue);

        await tester.tap(find.byIcon(Icons.logout));
        expect(taps, 1);
        handle.dispose();
      });

      testWidgets('is a 48 px target', (tester) async {
        await pumpApp(tester, wrap(entry.value, onPressed: () {}));
        final Size size = tester.getSize(find.byType(FocusRing));
        expect(size.width, greaterThanOrEqualTo(zenIconButtonSize));
        expect(size.height, greaterThanOrEqualTo(zenIconButtonSize));
      });

      testWidgets('Tab reaches it, Enter and Space activate it, and a ring shows', (tester) async {
        int taps = 0;
        await pumpApp(tester, wrap(entry.value, onPressed: () => taps++));
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
        await pumpApp(tester, wrap(entry.value, onPressed: () {}));
        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing)), isTrue);

        await tester.tap(find.byIcon(Icons.logout));
        await tester.pumpAndSettle();
        expect(isRinged(tester, find.byType(FocusRing)), isFalse);
      }, semanticsEnabled: false);

      testWidgets('disabled: announced as disabled, not tappable, not focusable', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, wrap(entry.value));

        expect(nodesWith(tester, SemanticsAction.tap), isEmpty);
        final SemanticsNode node = tester.getSemantics(find.byIcon(Icons.logout));
        expect(node.getSemanticsData().label, contains('Log out'));
        expect(isEnabled(node.getSemanticsData()), isFalse);

        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing)), isFalse);
        handle.dispose();
      });

      testWidgets('the icon is decorative: the label is the only name', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(tester, wrap(entry.value, onPressed: () {}));
        expect(occurrences(rootLabels(tester), 'Log out'), 1);
        handle.dispose();
      });

      testWidgets('keeps its size at 200% text on a narrow screen', (tester) async {
        await pumpApp(
          tester,
          wrap(entry.value, onPressed: () {}),
          size: const Size(260, 700),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(FocusRing)).height,
          greaterThanOrEqualTo(zenIconButtonSize),
        );
      });

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA non-text contrast (${theme.key})', (tester) async {
          await pumpApp(tester, wrap(entry.value, onPressed: () {}), theme: theme.value);
          final Icon icon = tester.widget<Icon>(find.byIcon(Icons.logout));
          final Color surface = theme.value.colorScheme.surface;
          final Color color = icon.color ?? IconTheme.of(tester.element(find.byType(Icon))).color!;
          // WCAG 1.4.11: a graphical object that identifies a control needs 3:1.
          expect(contrastRatio(color, surface), greaterThanOrEqualTo(3));
        });
      }
    });
  }
}

/// Every label a screen reader would read on the screen, joined.
String rootLabels(WidgetTester tester) {
  final StringBuffer out = StringBuffer();
  bool visit(SemanticsNode node) {
    if (!node.isMergedIntoParent) out.write('${node.getSemanticsData().label}|');
    node.visitChildren(visit);
    return true;
  }

  visit(rootSemantics(tester));
  return out.toString();
}
