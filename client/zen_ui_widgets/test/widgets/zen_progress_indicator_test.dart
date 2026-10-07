import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/zen_progress_indicator.dart';

import '../support/a11y.dart';

void main() {
  testWidgets('the Material spinner is a CircularProgressIndicator of the given size', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Builder(builder: (BuildContext c) => buildMaterialProgress(c, 20, null)),
      settle: false,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });

  testWidgets('the Cupertino spinner is a CupertinoActivityIndicator in the theme colour', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Builder(builder: (BuildContext c) => buildCupertinoProgress(c, 20, null)),
      settle: false,
    );
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('it is decorative: it adds nothing to the semantics tree', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpApp(tester, const ZenProgressIndicator(), settle: false);
    expect(
      find.descendant(
        of: find.byType(ZenProgressIndicator),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
    expect(tester.getSize(find.byType(ZenProgressIndicator)), const Size.square(36));
    handle.dispose();
  });
}
