import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import 'support/conflict_fixture.dart';

/// Whether the conflict screens are legible and named (WCAG 1.4.3 Contrast, 1.4.4 Resize Text,
/// 2.5.8 Target Size, 4.1.2 Name, Role, Value). They are built from zen_ui_widgets controls,
/// whose own suites cover each idiom; this checks the screens assembled from them.
void main() {
  late ConflictFixture fixture;

  tearDown(() async => fixture.dispose());

  final themes = <String, ThemeData>{
    for (final brightness in Brightness.values)
      brightness.name: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
      ),
  };

  Future<void> openVersions(WidgetTester tester, {ThemeData? theme}) async {
    fixture = (await tester.runAsync(ConflictFixture.create))!;
    await tester.pumpWidget(
      conflictApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              ZenConflictBanner(store: fixture.phone, sources: [fixture.source(fixture.phone)]),
              Expanded(
                child: ZenConflictResolveScreen(
                  conflict: fixture.source(fixture.phone).views(notSet: '-').dataOrNull!.single,
                  onResolved: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final entry in themes.entries) {
    testWidgets('the banner and the versions meet AA contrast and target size (${entry.key})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openVersions(tester, theme: entry.value);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  }

  testWidgets('a field is read as one node, label and value together', (tester) async {
    final handle = tester.ensureSemantics();
    await openVersions(tester);

    expect(find.bySemanticsLabel(RegExp(r'^Amount\n12\.50$')), findsOneWidget);
    expect(find.bySemanticsLabel('Keep this version'), findsNWidgets(2));
    handle.dispose();
  });

  testWidgets('the versions lay out at 200% text', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    fixture = (await tester.runAsync(ConflictFixture.create))!;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: conflictApp(
          home: ZenConflictsScreen(store: fixture.phone, sources: [fixture.source(fixture.phone)]),
        ),
      ),
    );
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
