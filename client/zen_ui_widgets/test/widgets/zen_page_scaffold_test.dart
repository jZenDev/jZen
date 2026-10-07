import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/zen_page_scaffold.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show ZenIconButton;

import '../support/a11y.dart';

typedef Build = Widget Function(BuildContext context, ZenPageScaffold page);

/// Both idioms are built directly: the public widget chooses one on a compile-time constant, so
/// one run only reaches the branch of the host it was compiled for.
final Map<String, Build> builds = <String, Build>{
  'material': buildMaterialPageScaffold,
  'cupertino': buildCupertinoPageScaffold,
};

/// A page whose build is [build], so the test reaches the idiom it names.
Widget page(
  Build build, {
  String? title = 'Profile',
  Widget? leading,
  VoidCallback? onBack,
  List<Widget> actions = const <Widget>[],
  bool implyLeading = true,
  Color? foreground,
  Widget body = const Center(child: Text('Body')),
}) => Builder(
  builder: (BuildContext context) => build(
    context,
    ZenPageScaffold(
      title: title,
      leading: leading,
      onBack: onBack,
      actions: actions,
      automaticallyImplyLeading: implyLeading,
      foregroundColor: foreground,
      body: body,
    ),
  ),
);

Future<void> pumpPage(
  WidgetTester tester,
  Widget home, {
  ThemeData? theme,
  Size size = const Size(800, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(MaterialApp(theme: theme, home: home));
  await tester.pumpAndSettle();
}

/// Pushes [route] over the app's home, so the page under test can pop.
Future<void> push(WidgetTester tester, Widget route) async {
  Navigator.of(
    tester.element(find.byType(Navigator)),
  ).push(MaterialPageRoute<void>(builder: (_) => route));
  await tester.pumpAndSettle();
}

ZenIconButton action(VoidCallback? onPressed, {String label = 'Log out'}) =>
    ZenIconButton(icon: Icons.logout, label: label, onPressed: onPressed);

List<SemanticsData> headings(WidgetTester tester) {
  final List<SemanticsData> found = <SemanticsData>[];
  bool visit(SemanticsNode node) {
    if (!node.isMergedIntoParent && node.getSemanticsData().flagsCollection.isHeader) {
      found.add(node.getSemanticsData());
    }
    node.visitChildren(visit);
    return true;
  }

  visit(rootSemantics(tester));
  return found;
}

void main() {
  for (final MapEntry<String, Build> entry in builds.entries) {
    group(entry.key, () {
      testWidgets('the title is one heading, named once', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpPage(tester, page(entry.value));

        final List<SemanticsData> found = headings(tester);
        expect(found, hasLength(1), reason: found.map((h) => h.label).join(' | '));
        expect(found.single.label, 'Profile');
        handle.dispose();
      });

      testWidgets('the body sits below the bar and its widgets work', (tester) async {
        await pumpPage(tester, page(entry.value, body: const ListTile(title: Text('Row'))));
        // A ListTile needs a Material ancestor; the Cupertino page supplies one.
        expect(tester.takeException(), isNull);
        final double barBottom = tester.getBottomLeft(find.text('Profile')).dy;
        expect(tester.getTopLeft(find.text('Row')).dy, greaterThan(barBottom));
      });

      testWidgets('a tappable ListTile renders and takes its tap', (tester) async {
        int taps = 0;
        await pumpPage(
          tester,
          page(
            entry.value,
            body: ListTile(title: const Text('Row'), onTap: () => taps++),
          ),
        );
        // ListTile asserts its ink is visible: a coloured box between it and its Material
        // fails that check, which a tile with no onTap never reaches.
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Row'));
        await tester.pump();
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('actions are named once each and tap', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        int taps = 0;
        await pumpPage(
          tester,
          page(
            entry.value,
            actions: <Widget>[
              action(() => taps++),
              action(() {}, label: 'Settings'),
            ],
          ),
        );

        final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.tap);
        expect(nodes.map((n) => n.label), <String>['Log out', 'Settings']);

        await tester.tap(find.byIcon(Icons.logout).first);
        expect(taps, 1);
        handle.dispose();
      });

      testWidgets('Tab reaches an action, Enter activates it, and a ring shows', (tester) async {
        int taps = 0;
        await pumpPage(tester, page(entry.value, actions: <Widget>[action(() => taps++)]));
        expect(isRinged(tester, find.byType(ZenIconButton)), isFalse);

        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(ZenIconButton)), isTrue);
        await press(tester, LogicalKeyboardKey.enter);
        expect(taps, 1);
      }, semanticsEnabled: false);

      testWidgets('a page at the root has no back button', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpPage(tester, page(entry.value));
        expect(nodesWith(tester, SemanticsAction.tap), isEmpty);
        handle.dispose();
      });

      testWidgets('a pushed page shows a back button that pops', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpPage(tester, const Text('Root'));
        await push(tester, page(entry.value));

        final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.tap);
        expect(nodes.map((n) => n.label), <String>['Back']);
        expect(nodes.single.flagsCollection.isButton, isTrue);

        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(ZenIconButton)), isTrue);

        await tester.tap(find.byType(ZenIconButton));
        await tester.pumpAndSettle();
        expect(find.text('Profile'), findsNothing);
        expect(find.text('Root'), findsOneWidget);
        handle.dispose();
      });

      testWidgets('leading replaces the implied back; implyLeading false removes it', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpPage(tester, const Text('Root'));
        await push(tester, page(entry.value, leading: action(() {}, label: 'Close')));
        expect(nodesWith(tester, SemanticsAction.tap).map((n) => n.label), <String>['Close']);

        await push(tester, page(entry.value, implyLeading: false));
        expect(nodesWith(tester, SemanticsAction.tap), isEmpty);
        handle.dispose();
      });

      testWidgets('onBack shows a Back button at the root and calls it', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        int backs = 0;
        await pumpPage(tester, page(entry.value, onBack: () => backs++));
        expect(nodesWith(tester, SemanticsAction.tap).map((n) => n.label), <String>['Back']);

        await tester.tap(find.byType(ZenIconButton));
        expect(backs, 1);
        handle.dispose();
      });

      testWidgets('with no title, leading or actions there is no bar', (tester) async {
        await pumpPage(tester, page(entry.value, title: null));
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(CupertinoNavigationBar), findsNothing);
        expect(find.text('Body'), findsOneWidget);
      });

      testWidgets('foregroundColor colours the title and the icons', (tester) async {
        await pumpPage(
          tester,
          page(entry.value, foreground: Colors.teal, actions: <Widget>[action(() {})]),
        );
        // The colour the text paints: its own style over the bar's default.
        final Finder title = find.text('Profile');
        final TextStyle painted = DefaultTextStyle.of(
          tester.element(title),
        ).style.merge(tester.widget<Text>(title).style);
        expect(painted.color, Colors.teal);
        expect(IconTheme.of(tester.element(find.byIcon(Icons.logout))).color, Colors.teal);
      });

      testWidgets('keeps the bar usable at 200% text on a narrow screen', (tester) async {
        await pumpPage(
          tester,
          page(
            entry.value,
            title: 'A rather long page title that cannot fit',
            actions: <Widget>[
              action(() {}),
              action(() {}, label: 'Settings'),
            ],
          ),
          size: const Size(260, 700),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Body'), findsOneWidget);
      });

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA contrast (${theme.key})', (tester) async {
          await pumpPage(
            tester,
            page(entry.value, actions: <Widget>[action(() {})]),
            theme: theme.value,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          // WCAG 1.4.11: the icon identifies a control, so it needs 3:1 against the bar.
          final Color icon = IconTheme.of(tester.element(find.byIcon(Icons.logout))).color!;
          final Color bar = theme.value.colorScheme.surface;
          expect(contrastRatio(icon, bar), greaterThanOrEqualTo(3));
        });
      }
    });
  }
}
