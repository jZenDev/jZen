import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/zen_list_row.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../support/a11y.dart';

void main() {
  for (final apple in [true, false]) {
    testWidgets('list row supports tap and keyboard (apple: $apple)', (tester) async {
      var taps = 0;
      await pumpApp(
        tester,
        Builder(
          builder: (context) => FocusRing.wrapping(
            child: buildZenListRow(context, 'Account', 'Details', () => taps++, apple: apple),
          ),
        ),
      );
      await tester.tap(find.text('Account'));
      expect(taps, 1);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.enter);
      expect(taps, 2);
      if (apple) {
        final context = tester.element(find.byType(ListTile));
        expect(Theme.of(context).splashFactory, NoSplash.splashFactory);
        expect(Theme.of(context).highlightColor, Colors.transparent);
      }
    });
  }
}
