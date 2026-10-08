import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  group('the pushed page on macOS', () {
    testWidgets('fades in without sliding from the right', (tester) async {
      final Finder pushed = await midPush(tester, TargetPlatform.macOS, zen);
      expect(
        tester.getTopLeft(pushed).dx,
        lessThan(40),
        reason: 'a slide would still be far right',
      );
      expect(find.byType(FadeTransition), findsWidgets);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(pushed).dx, lessThan(40));
    });

    testWidgets('a plain MaterialPageRoute follows the theme the app passes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            platform: TargetPlatform.macOS,
            pageTransitionsTheme: ZenPageTransitions.theme,
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

  testWidgets('the fade is short and reaches full opacity', (tester) async {
    const ZenFadePageTransitionsBuilder fade = ZenFadePageTransitionsBuilder();
    expect(fade.transitionDuration, lessThanOrEqualTo(const Duration(milliseconds: 250)));
    final Finder pushed = await midPush(tester, TargetPlatform.macOS, zen);
    await tester.pumpAndSettle();
    final FadeTransition t = tester.widget<FadeTransition>(
      find.ancestor(of: pushed, matching: find.byType(FadeTransition)).first,
    );
    expect(t.opacity.value, 1);
  });
}
