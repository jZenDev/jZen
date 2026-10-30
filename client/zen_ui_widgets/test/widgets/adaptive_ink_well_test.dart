import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../support/a11y.dart';

void main() {
  testWidgets('public target follows the platform and supports input and semantics', (
    tester,
  ) async {
    var taps = 0;
    const radius = BorderRadius.all(Radius.circular(12));
    final handle = tester.ensureSemantics();
    await pumpApp(
      tester,
      AdaptiveInkWell(
        onTap: () => taps++,
        borderRadius: radius,
        child: const SizedBox(width: 100, height: 48, child: Text('Open goal')),
      ),
    );
    final ink = tester.widget<InkWell>(find.byType(InkWell));
    expect(ink.borderRadius, radius);
    expect(ink.splashFactory, zenIsApplePlatform ? NoSplash.splashFactory : null);
    if (zenIsApplePlatform) {
      expect(ink.highlightColor, Colors.transparent);
      expect(ink.hoverColor, Colors.transparent);
    }
    final nodes = nodesWith(tester, SemanticsAction.tap);
    expect(nodes, hasLength(1));
    expect(nodes.single.label, contains('Open goal'));
    await tester.tap(find.text('Open goal'));
    await press(tester, LogicalKeyboardKey.tab);
    expect(isRinged(tester, find.byType(FocusRing)), isTrue);
    await press(tester, LogicalKeyboardKey.space);
    await press(tester, LogicalKeyboardKey.enter);
    expect(taps, 3);
    handle.dispose();
  });

  testWidgets('disabled target has no activation', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(
      tester,
      const AdaptiveInkWell(
        onTap: null,
        child: SizedBox(width: 100, height: 48, child: Text('Open goal')),
      ),
    );
    expect(nodesWith(tester, SemanticsAction.tap), isEmpty);
    await press(tester, LogicalKeyboardKey.tab);
    expect(isRinged(tester, find.byType(FocusRing)), isFalse);
    handle.dispose();
  });
}
