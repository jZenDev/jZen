import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/zen_page_scaffold.dart' show buildCupertinoPageScaffold;
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// Pumps a home page, pushes [route] and stops 60 ms into the transition, where a slide has moved
/// the new page and a fade has not.
Future<Finder> midPush(
  WidgetTester tester,
  TargetPlatform platform,
  Route<void> Function(WidgetBuilder page) route,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: const Scaffold(body: Text('Home')),
    ),
  );
  Navigator.of(tester.element(find.text('Home'))).push(
    route(
      (_) => const Scaffold(
        body: Align(alignment: Alignment.topLeft, child: Text('Pushed')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  return find.text('Pushed');
}

void main() {
  Route<void> zen(WidgetBuilder b) => ZenPageRoute<void>(builder: b);

  // `ZenPageRoute` follows the build's `ZEN_PLATFORM`, so a run reaches one branch of this;
  // `themeFor` below reaches both.
  group('the pushed page under TargetPlatform.macOS', () {
    testWidgets('fades in without sliding from the right in a macOS build only', (tester) async {
      final Finder pushed = await midPush(tester, TargetPlatform.macOS, zen);
      if (zenIsMacOS) {
        expect(
          tester.getTopLeft(pushed).dx,
          lessThan(40),
          reason: 'a slide would still be far right',
        );
        expect(find.byType(FadeTransition), findsWidgets);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(pushed).dx, lessThan(40));
      } else {
        // A browser on a Mac reports TargetPlatform.macOS too; it is a Material build, not a Mac
        // window, so it keeps Flutter's own slide.
        expect(tester.getTopLeft(pushed).dx, greaterThan(100));
      }
    });

    testWidgets('a plain MaterialPageRoute follows the theme the app passes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            platform: TargetPlatform.macOS,
            pageTransitionsTheme: ZenPageTransitions.themeFor(macOS: true),
          ),
          home: const Scaffold(body: Text('Home')),
        ),
      );
      Navigator.of(tester.element(find.text('Home'))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            body: Align(alignment: Alignment.topLeft, child: Text('Pushed')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(find.text('Pushed')).dx, lessThan(40));
    });

    testWidgets('Flutter\'s own default is the slide, which is what this replaces', (tester) async {
      final Finder pushed = await midPush(
        tester,
        TargetPlatform.macOS,
        (WidgetBuilder b) => MaterialPageRoute<void>(builder: b),
      );
      expect(tester.getTopLeft(pushed).dx, greaterThan(100));
    });
  });

  group('the pushed page elsewhere', () {
    testWidgets('keeps the slide on iOS', (tester) async {
      final Finder pushed = await midPush(tester, TargetPlatform.iOS, zen);
      expect(tester.getTopLeft(pushed).dx, greaterThan(100));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(pushed).dx, 0);
    });

    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      testWidgets('leaves ${platform.name} on Flutter\'s default', (tester) async {
        expect(
          ZenPageTransitions.theme.builders[platform].runtimeType,
          const PageTransitionsTheme().builders[platform].runtimeType,
        );
      });
    }
  });

  group('which build gets the fade', () {
    test('a macOS build fades TargetPlatform.macOS', () {
      expect(
        ZenPageTransitions.themeFor(macOS: true).builders[TargetPlatform.macOS],
        isA<ZenFadePageTransitionsBuilder>(),
      );
    });

    test('any other build leaves TargetPlatform.macOS on Flutter\'s default', () {
      // A web build on a Mac lands here: Flutter calls the browser TargetPlatform.macOS.
      final PageTransitionsBuilder? builder = ZenPageTransitions.themeFor(
        macOS: false,
      ).builders[TargetPlatform.macOS];
      expect(builder, isNot(isA<ZenFadePageTransitionsBuilder>()));
      expect(
        builder.runtimeType,
        const PageTransitionsTheme().builders[TargetPlatform.macOS].runtimeType,
      );
    });

    test('this build\'s theme is the one its ZEN_PLATFORM names', () {
      expect(
        ZenPageTransitions.theme.builders[TargetPlatform.macOS],
        zenIsMacOS
            ? isA<ZenFadePageTransitionsBuilder>()
            : isNot(isA<ZenFadePageTransitionsBuilder>()),
      );
    });

    test('no other platform changes with the build', () {
      for (final TargetPlatform p in TargetPlatform.values.where(
        (p) => p != TargetPlatform.macOS,
      )) {
        expect(
          ZenPageTransitions.themeFor(macOS: true).builders[p].runtimeType,
          ZenPageTransitions.themeFor(macOS: false).builders[p].runtimeType,
        );
      }
    });
  });

  // The page that slides on a Mac is the Cupertino navigation bar's hero, which a bare Scaffold
  // does not have and the page transition does not govern; so these push `ZenPageScaffold` pages
  // and read where the title is, not what widget types are in the tree.
  group('the navigation bar of a pushed ZenPageScaffold', () {
    Future<List<double>> titleTravel(
      WidgetTester tester, {
      required TargetPlatform platform,
      required bool macOSBuild,
    }) async {
      Widget page(BuildContext context, String title, {List<Widget> actions = const <Widget>[]}) =>
          buildCupertinoPageScaffold(
            context,
            ZenPageScaffold(
              title: title,
              actions: actions,
              body: const Center(child: Text('Body')),
            ),
            macOS: macOSBuild,
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            platform: platform,
            pageTransitionsTheme: ZenPageTransitions.themeFor(macOS: macOSBuild),
          ),
          home: Builder(
            builder: (BuildContext context) => page(
              context,
              'Overview',
              actions: <Widget>[
                ZenIconButton(
                  icon: Icons.add,
                  label: 'go',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (BuildContext c) => page(c, 'Reminders')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ZenIconButton));
      await tester.pump();
      final List<double> dx = <double>[];
      for (final int ms in <int>[1, 40, 40, 40, 40, 40]) {
        await tester.pump(Duration(milliseconds: ms));
        dx.add(tester.getTopLeft(find.text('Reminders').last).dx);
      }
      await tester.pumpAndSettle();
      dx.add(tester.getTopLeft(find.text('Reminders')).dx);
      return dx;
    }

    testWidgets('stays put while the page fades, on a macOS build', (tester) async {
      final List<double> dx = await titleTravel(
        tester,
        platform: TargetPlatform.macOS,
        macOSBuild: true,
      );
      expect(dx.toSet(), hasLength(1), reason: 'the title travelled: $dx');
    });

    testWidgets('keeps the iOS hero on an iOS build', (tester) async {
      final List<double> dx = await titleTravel(
        tester,
        platform: TargetPlatform.iOS,
        macOSBuild: false,
      );
      expect(dx.first, greaterThan(dx.last + 100), reason: 'the title should fly in: $dx');
    });

    testWidgets('keeps the hero in a browser on a Mac, which is not a macOS build', (tester) async {
      final List<double> dx = await titleTravel(
        tester,
        platform: TargetPlatform.macOS,
        macOSBuild: false,
      );
      expect(dx.first, greaterThan(dx.last + 100), reason: 'the title should fly in: $dx');
    });
  });

  testWidgets('the fade is short and reaches full opacity', (tester) async {
    const ZenFadePageTransitionsBuilder fade = ZenFadePageTransitionsBuilder();
    expect(fade.transitionDuration, lessThanOrEqualTo(const Duration(milliseconds: 250)));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          platform: TargetPlatform.macOS,
          pageTransitionsTheme: ZenPageTransitions.themeFor(macOS: true),
        ),
        home: const Scaffold(body: Text('Home')),
      ),
    );
    Navigator.of(
      tester.element(find.text('Home')),
    ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Pushed'))));
    await tester.pumpAndSettle();
    final FadeTransition t = tester.widget<FadeTransition>(
      find.ancestor(of: find.text('Pushed'), matching: find.byType(FadeTransition)).first,
    );
    expect(t.opacity.value, 1);
  });
}
