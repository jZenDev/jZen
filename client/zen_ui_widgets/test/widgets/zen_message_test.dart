import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/zen_message.dart';

import '../support/a11y.dart';

typedef Show =
    void Function(
      BuildContext context,
      String message, {
      Color? backgroundColor,
      String? actionLabel,
      VoidCallback? onAction,
    });

/// Both idioms are called directly: the public function chooses one on a compile-time constant,
/// so one run only reaches the branch of the host it was compiled for.
final Map<String, Show> shows = <String, Show>{
  'material': showMaterialZenMessage,
  'cupertino': showCupertinoZenMessage,
};

Future<BuildContext> pumpScreen(
  WidgetTester tester, {
  ThemeData? theme,
  bool accessibleNavigation = false,
}) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(accessibleNavigation: accessibleNavigation),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(builder: (BuildContext c) => Text('Screen', key: Key('$c'))),
      ),
    ),
  );
  context = tester.element(find.text('Screen'));
  return context;
}

void main() {
  for (final MapEntry<String, Show> entry in shows.entries) {
    group(entry.key, () {
      testWidgets('shows the message, then removes it', (tester) async {
        final BuildContext context = await pumpScreen(tester);
        entry.value(context, 'Saved');
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.text('Saved'), findsOneWidget);

        await tester.pump(zenMessageDuration + const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Saved'), findsNothing);
      });

      testWidgets('a new message replaces the one showing', (tester) async {
        final BuildContext context = await pumpScreen(tester);
        entry.value(context, 'First');
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        entry.value(context, 'Second');
        await tester.pumpAndSettle(const Duration(milliseconds: 100));

        expect(find.text('First'), findsNothing);
        expect(find.text('Second'), findsOneWidget);
        await tester.pump(zenMessageDuration * 2);
        await tester.pumpAndSettle();
      });

      testWidgets('is read once, as a live region', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final BuildContext context = await pumpScreen(tester);
        entry.value(context, 'Saved');
        await tester.pumpAndSettle(const Duration(milliseconds: 100));

        final List<SemanticsData> found = <SemanticsData>[];
        bool visit(SemanticsNode node) {
          final SemanticsData data = node.getSemanticsData();
          if (!node.isMergedIntoParent && data.label.contains('Saved')) found.add(data);
          node.visitChildren(visit);
          return true;
        }

        visit(rootSemantics(tester));
        expect(found, hasLength(1), reason: found.map((d) => d.label).join(' | '));
        expect(found.single.flagsCollection.isLiveRegion, isTrue);

        await tester.pump(zenMessageDuration * 2);
        await tester.pumpAndSettle();
        handle.dispose();
      });

      testWidgets('an action runs its callback once and dismisses the message', (tester) async {
        final BuildContext context = await pumpScreen(tester);
        int undone = 0;
        entry.value(context, 'Deleted', actionLabel: 'Undo', onAction: () => undone++);
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.text('Undo'), findsOneWidget);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(undone, 1);
        expect(find.text('Deleted'), findsNothing);
      });

      testWidgets('the action is its own named button, beside the message read once', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final BuildContext context = await pumpScreen(tester);
        entry.value(context, 'Deleted', actionLabel: 'Undo', onAction: () {});
        await tester.pumpAndSettle(const Duration(milliseconds: 100));

        final List<SemanticsData> buttons = nodesWith(
          tester,
          SemanticsAction.tap,
        ).where((SemanticsData d) => d.label.contains('Undo')).toList();
        expect(buttons, hasLength(1), reason: 'the action is not one named node');
        expect(buttons.single.flagsCollection.isButton, isTrue);
        expect(buttons.single.label, isNot(contains('Deleted')));

        final List<SemanticsData> live = <SemanticsData>[];
        bool visit(SemanticsNode node) {
          final SemanticsData data = node.getSemanticsData();
          if (!node.isMergedIntoParent && data.label.contains('Deleted')) live.add(data);
          node.visitChildren(visit);
          return true;
        }

        visit(rootSemantics(tester));
        expect(live, hasLength(1), reason: live.map((d) => d.label).join(' | '));

        await tester.pump(zenMessageDuration * 2);
        await tester.pumpAndSettle();
        handle.dispose();
      });

      testWidgets('a message with an action stays until it is dealt with', (tester) async {
        final BuildContext context = await pumpScreen(tester, accessibleNavigation: true);
        entry.value(context, 'Deleted', actionLabel: 'Undo', onAction: () {});
        await tester.pumpAndSettle(const Duration(milliseconds: 100));

        await tester.pump(zenMessageDuration * 10);
        await tester.pumpAndSettle();
        expect(find.text('Deleted'), findsOneWidget);

        // A tap on the toast, or the snack bar's close icon, dismisses it.
        await tester.tap(
          entry.key == 'cupertino' ? find.text('Deleted') : find.byIcon(Icons.close),
        );
        await tester.pumpAndSettle();
        expect(find.text('Deleted'), findsNothing);
      });

      testWidgets('without an action there is no button', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final BuildContext context = await pumpScreen(tester);
        entry.value(context, 'Saved');
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.byType(TextButton), findsNothing);
        expect(find.text('Undo'), findsNothing);
        await tester.pump(zenMessageDuration * 2);
        await tester.pumpAndSettle();
        handle.dispose();
      });

      for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
        testWidgets('meets AA text contrast (${theme.key})', (tester) async {
          final BuildContext context = await pumpScreen(tester, theme: theme.value);
          entry.value(context, 'Saved');
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          await expectLater(tester, meetsGuideline(textContrastGuideline));

          // An app's own colour, light and dark, still gets readable text.
          entry.value(context, 'Failed', backgroundColor: theme.value.colorScheme.error);
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          expect(find.text('Failed'), findsOneWidget);
          await expectLater(tester, meetsGuideline(textContrastGuideline));

          // The action's text is held to the same bar, on the theme's colour and on an app's.
          entry.value(context, 'Deleted', actionLabel: 'Undo', onAction: () {});
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          entry.value(
            context,
            'Deleted',
            backgroundColor: theme.value.colorScheme.error,
            actionLabel: 'Undo',
            onAction: () {},
          );
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await tester.pump(zenMessageDuration * 2);
          await tester.pumpAndSettle();
        });
      }
    });
  }

  group('cupertino', () {
    testWidgets('does not need a Scaffold', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Text('Screen')));
      showCupertinoZenMessage(tester.element(find.text('Screen')), 'Saved');
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Saved'), findsOneWidget);
      await tester.pump(zenMessageDuration * 2);
      await tester.pumpAndSettle();
    });

    testWidgets('a tap dismisses it', (tester) async {
      final BuildContext context = await pumpScreen(tester);
      showCupertinoZenMessage(context, 'Saved');
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsNothing);
    });

    testWidgets('stays longer when assistive navigation is on', (tester) async {
      final BuildContext context = await pumpScreen(tester, accessibleNavigation: true);
      showCupertinoZenMessage(context, 'Saved');
      await tester.pump(zenMessageDuration + const Duration(seconds: 1));
      expect(find.text('Saved'), findsOneWidget);
      await tester.pump(zenMessageDuration * 3);
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsNothing);
    });

    testWidgets('keeps the message readable at 200% text on a narrow screen', (tester) async {
      tester.view.physicalSize = const Size(260, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final BuildContext context = await pumpScreen(tester);
      showCupertinoZenMessage(context, 'Your changes were saved successfully');
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Your changes were saved successfully'), findsOneWidget);
      await tester.pump(zenMessageDuration * 2);
      await tester.pumpAndSettle();
    });
  });
}
