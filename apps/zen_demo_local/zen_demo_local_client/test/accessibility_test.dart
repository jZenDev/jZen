import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// Whether the app's screens are legible and named (WCAG 1.4.3 Contrast, 1.4.4 Resize Text,
/// 2.5.8 Target Size, 4.1.2 Name, Role, Value). The controls' own suites cover each idiom; this
/// checks the screens assembled from them.
void main() {
  Future<void> expectAccessible(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  }

  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      setUp(() {});

      Future<AppHarness> open(WidgetTester tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        return AppHarness.pump(
          tester,
          seed: (d) async {
            await twoChores(d);
            await titleConflict(d);
          },
        );
      }

      testWidgets('the list with both banners', (tester) async {
        final handle = tester.ensureSemantics();
        await open(tester);
        await expectAccessible(tester);
        handle.dispose();
      });

      testWidgets('the form', (tester) async {
        final handle = tester.ensureSemantics();
        final app = await open(tester);
        await app.tapText('Add a chore');
        await expectAccessible(tester);
        handle.dispose();
      });

      testWidgets('the settings', (tester) async {
        final handle = tester.ensureSemantics();
        final app = await open(tester);
        await app.tapLabel('Settings');
        await expectAccessible(tester);
        handle.dispose();
      });
    });
  }

  testWidgets('the list lays out at 200% text', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await AppHarness.pump(tester, seed: twoChores);

    expect(tester.takeException(), isNull);
    expect(find.text('Dishes'), findsOneWidget);
  });
}
