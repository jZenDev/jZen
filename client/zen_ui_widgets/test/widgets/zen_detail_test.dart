import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/zen_detail_host.dart';
import 'package:zen_ui_widgets/src/zen_detail_pane.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

const Size wide = Size(1000, 800);
const Size narrow = Size(500, 800);

/// A list with an "Open" button; [opened] collects the futures `showZenDetail` returns.
Widget list(List<Future<Object?>> opened, {WidgetBuilder? detail, ScrollController? scroll}) {
  return Builder(
    builder: (BuildContext context) => Scaffold(
      body: ListView(
        controller: scroll,
        children: <Widget>[
          const Text('List'),
          ZenButton(
            label: 'Open',
            onPressed: () => opened.add(
              showZenDetail<Object?>(context, builder: detail ?? (_) => const _Goal('Goal')),
            ),
          ),
          for (int i = 0; i < 40; i++) Text('Row $i'),
        ],
      ),
    ),
  );
}

class _Goal extends StatelessWidget {
  const _Goal(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return ZenPageScaffold(
      title: title,
      body: Column(
        children: <Widget>[
          ZenButton(label: 'Save', onPressed: () => Navigator.of(context).pop('saved')),
          ZenButton(
            label: 'Deeper',
            onPressed: () => showZenDetail<void>(context, builder: (_) => const _Goal('Deeper')),
          ),
        ],
      ),
    );
  }
}

Future<void> pumpHost(
  WidgetTester tester,
  Widget home, {
  Size size = wide,
  bool host = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: ZenWidgetsLocalizations.localizationsDelegates,
      supportedLocales: ZenWidgetsLocalizations.supportedLocales,
      home: host ? ZenDetailHost(child: home) : home,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('on a wide host', () {
    testWidgets('opens beside the list, which stays', (tester) async {
      final List<Future<Object?>> opened = <Future<Object?>>[];
      await pumpHost(tester, list(opened));
      final double listWidth = tester.getSize(find.byType(ListView)).width;

      await open(tester);

      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('List'), findsOneWidget);
      final double paneWidth = tester.getSize(find.byType(ZenDetailPane)).width;
      expect(paneWidth, inInclusiveRange(320, 420));
      expect(tester.getTopLeft(find.byType(ZenDetailPane)).dx, wide.width - paneWidth);
      if (zenIsApplePlatform) {
        // An in-layout pane takes room from the list.
        expect(tester.getSize(find.byType(ListView)).width, listWidth - paneWidth - 1);
      } else {
        // A side sheet covers the list's trailing edge and leaves its layout alone.
        expect(tester.getSize(find.byType(ListView)).width, listWidth);
      }
    });

    testWidgets('the list keeps its scroll position while a detail opens and closes', (
      tester,
    ) async {
      final ScrollController scroll = ScrollController();
      addTearDown(scroll.dispose);
      final List<Future<Object?>> opened = <Future<Object?>>[];
      await pumpHost(tester, list(opened, scroll: scroll));
      scroll.jumpTo(10);
      await tester.pump();

      await open(tester);
      expect(scroll.offset, 10);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(scroll.offset, 10);
    });

    testWidgets('the first page offers Close, and Close dismisses with null', (tester) async {
      final List<Future<Object?>> opened = <Future<Object?>>[];
      await pumpHost(tester, list(opened));
      await open(tester);
      expect(find.bySemanticsLabel('Back'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Goal'), findsNothing);
      expect(await opened.single, isNull);
    });

    testWidgets('Navigator.pop(result) completes the future and closes the pane', (tester) async {
      final List<Future<Object?>> opened = <Future<Object?>>[];
      await pumpHost(tester, list(opened));
      await open(tester);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Goal'), findsNothing);
      expect(await opened.single, 'saved');
      // The page beneath was not popped.
      expect(find.text('List'), findsOneWidget);
    });

    testWidgets('the pane reflows at 200% text with no overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final List<Future<Object?>> opened = <Future<Object?>>[];
      await pumpHost(tester, list(opened));
      await open(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Goal'), findsOneWidget);
    });

    testWidgets('Escape dismisses', (tester) async {
      final List<Future<Object?>> opened = <Future<Object?>>[];
      await pumpHost(tester, list(opened));
      await open(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Goal'), findsNothing);
      expect(await opened.single, isNull);
    });

    testWidgets('a second detail replaces the first, which ends with null', (tester) async {
      final List<Future<Object?>> opened = <Future<Object?>>[];
      int n = 0;
      await pumpHost(tester, list(opened, detail: (_) => _Goal('Goal ${++n}')));
      await open(tester);
      await open(tester);

      expect(find.text('Goal 1'), findsNothing);
      expect(find.text('Goal 2'), findsOneWidget);
      expect(await opened.first, isNull);
    });

    testWidgets('a detail opened from a detail stacks in the pane and offers Back', (tester) async {
      final List<Future<Object?>> opened = <Future<Object?>>[];
      await pumpHost(tester, list(opened));
      await open(tester);

      await tester.tap(find.text('Deeper'));
      await tester.pumpAndSettle();
      expect(find.text('Deeper', skipOffstage: true), findsWidgets);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      expect(find.text('List'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Goal'), findsOneWidget);
    });

    testWidgets('focus moves into the pane and returns to the opener', (tester) async {
      final List<Future<Object?>> opened = <Future<Object?>>[];
      await pumpHost(tester, list(opened));
      final Finder openButton = find.text('Open');
      Element openerOf() => tester.element(openButton);

      Focus.of(openerOf()).requestFocus();
      await tester.pump();
      final FocusNode? opener = FocusManager.instance.primaryFocus;

      await open(tester);
      final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
      expect(focused, isNotNull);
      expect(
        find.descendant(
          of: find.byType(ZenDetailPane),
          matching: find.byElementPredicate((e) => e == focused),
        ),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, opener);
    });

    testWidgets('narrowing the window carries an open detail over to a push', (tester) async {
      final List<Future<Object?>> opened = <Future<Object?>>[];
      await pumpHost(tester, list(opened));
      await open(tester);

      tester.view.physicalSize = narrow;
      await tester.pumpAndSettle();

      expect(find.byType(ZenDetailPane), findsNothing);
      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('List'), findsNothing, reason: 'the push covers the list');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(await opened.single, 'saved');
      expect(find.text('List'), findsOneWidget);
    });
  });

  group('on a narrow host', () {
    testWidgets('pushes a full-screen page; Back returns with null', (tester) async {
      final List<Future<Object?>> opened = <Future<Object?>>[];
      await pumpHost(tester, list(opened), size: narrow);
      await open(tester);

      expect(find.byType(ZenDetailPane), findsNothing);
      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('List'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      expect(find.text('List'), findsOneWidget);
      expect(await opened.single, isNull);
    });

    testWidgets('the width that counts is the host\'s, not the window\'s', (tester) async {
      final List<Future<Object?>> opened = <Future<Object?>>[];
      await pumpHost(
        tester,
        Row(
          children: <Widget>[
            const SizedBox(width: 400),
            Expanded(child: ZenDetailHost(child: list(opened))),
          ],
        ),
        host: false,
      );
      await open(tester);
      expect(find.byType(ZenDetailPane), findsNothing, reason: '600 px of host is narrow');
    });
  });

  testWidgets('without a host it is a push, even in a wide window', (tester) async {
    final List<Future<Object?>> opened = <Future<Object?>>[];
    await pumpHost(tester, list(opened), host: false);
    await open(tester);
    expect(find.byType(ZenDetailPane), findsNothing);
    expect(find.text('List'), findsNothing);
    expect(find.text('Goal'), findsOneWidget);
  });

  testWidgets('removing the host while a detail is open ends its future with null', (tester) async {
    final List<Future<Object?>> opened = <Future<Object?>>[];
    await pumpHost(tester, list(opened));
    await open(tester);
    await tester.pumpWidget(const SizedBox());
    expect(await opened.single, isNull);
  });

  group('the two idioms, built directly', () {
    Future<void> pumpPanes(WidgetTester tester, Widget Function(BuildContext) build) async {
      tester.view.physicalSize = wide;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: build)));
      await tester.pumpAndSettle();
    }

    const Key listKey = Key('list');
    const Key paneKey = Key('pane');

    testWidgets('Apple: the list narrows to make room', (tester) async {
      await pumpPanes(
        tester,
        (c) => buildApplePanes(
          c,
          const SizedBox.expand(key: listKey),
          const SizedBox.expand(key: paneKey),
          400,
        ),
      );
      expect(tester.getSize(find.byKey(paneKey)).width, 400);
      expect(tester.getSize(find.byKey(listKey)).width, wide.width - 400 - 1);
    });

    testWidgets('Material: a sheet over the list, which keeps its width', (tester) async {
      await pumpPanes(
        tester,
        (c) => buildMaterialPanes(
          c,
          const SizedBox.expand(key: listKey),
          const SizedBox.expand(key: paneKey),
          400,
        ),
      );
      expect(tester.getSize(find.byKey(paneKey)).width, 400);
      expect(tester.getSize(find.byKey(listKey)).width, wide.width);
      expect(tester.getTopLeft(find.byKey(paneKey)).dx, wide.width - 400);
    });

    testWidgets('with no pane both are just the list', (tester) async {
      for (final Widget Function(BuildContext, Widget, Widget?, double) build
          in <Widget Function(BuildContext, Widget, Widget?, double)>[
            buildApplePanes,
            buildMaterialPanes,
          ]) {
        await pumpPanes(tester, (c) => build(c, const SizedBox.expand(key: listKey), null, 400));
        expect(tester.getSize(find.byKey(listKey)), wide);
      }
    });
  });
}
