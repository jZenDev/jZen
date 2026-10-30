import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/zen_list_row.dart';

import '../support/a11y.dart';

Widget buildTestListRow(
  BuildContext context,
  String title,
  String? subtitle,
  VoidCallback? onTap, {
  required bool isApple,
  Widget? leading,
  Widget? trailing,
  bool enabled = true,
}) {
  final row = ZenListRow(
    title: title,
    subtitle: subtitle,
    onTap: onTap,
    leading: leading,
    trailing: trailing,
    enabled: enabled,
  );
  return isApple ? buildCupertinoListRow(context, row) : buildMaterialListRow(context, row);
}

void main() {
  for (final isApple in [true, false]) {
    testWidgets('rich row supports independent action and keyboard (isApple: $isApple)', (
      tester,
    ) async {
      var taps = 0;
      var actions = 0;
      await pumpApp(
        tester,
        Builder(
          builder: (context) => buildTestListRow(
            context,
            'Account',
            'Details',
            () => taps++,
            isApple: isApple,
            leading: const Icon(Icons.account_balance),
            trailing: IconButton(
              onPressed: () => actions++,
              icon: const Icon(Icons.edit),
              tooltip: 'Edit',
            ),
          ),
        ),
      );
      expect(find.byType(isApple ? CupertinoListTile : ListTile), findsOneWidget);
      await tester.tap(find.byTooltip('Edit'));
      expect(actions, 1);
      expect(taps, 0);
      await tester.tap(find.text('Account'));
      expect(taps, 1);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.enter);
      expect(taps, 2);
    });

    testWidgets('disabled and non-interactive rows (isApple: $isApple)', (tester) async {
      var taps = 0;
      await pumpApp(
        tester,
        Builder(
          builder: (context) => buildTestListRow(
            context,
            'Account',
            null,
            () => taps++,
            isApple: isApple,
            enabled: false,
          ),
        ),
      );
      await tester.tap(find.text('Account'));
      expect(taps, 0);
      expect(
        tester.getSemantics(find.text('Account')),
        matchesSemantics(
          label: 'Account',
          hasEnabledState: true,
          isEnabled: false,
          hasSelectedState: !isApple,
        ),
      );
    });

    testWidgets('long text fits narrow row (isApple: $isApple)', (tester) async {
      await pumpApp(
        tester,
        Center(
          child: SizedBox(
            width: 200,
            child: Builder(
              builder: (context) => buildTestListRow(
                context,
                'A long localized account name ' * 5,
                'A long localized description ' * 5,
                null,
                isApple: isApple,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Cupertino row reflows a trailing amount at 254 pixels', (tester) async {
    const title = 'A long localized account name';
    const subtitle = '30 October 2026 — a long localized note';
    const amount = '12 345 678,90 ₴';
    for (final scale in [1.0, 2.0]) {
      await pumpApp(
        tester,
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(
              width: 254,
              child: Builder(
                builder: (context) => buildTestListRow(
                  context,
                  title,
                  subtitle,
                  () {},
                  isApple: true,
                  leading: const Icon(Icons.account_balance),
                  trailing: const Text(amount),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(amount), findsOneWidget);
      expect(tester.getSemantics(find.text(amount)).label, contains(amount));
    }
  });

  testWidgets('reflowed trailing control remains independently operable', (tester) async {
    var taps = 0;
    var actions = 0;
    await pumpApp(
      tester,
      Center(
        child: SizedBox(
          width: 254,
          child: Builder(
            builder: (context) => buildTestListRow(
              context,
              'Account',
              'Details',
              () => taps++,
              isApple: true,
              leading: const Icon(Icons.account_balance),
              trailing: IconButton(
                onPressed: () => actions++,
                icon: const Icon(Icons.edit),
                tooltip: 'Edit',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Edit'));
    expect(actions, 1);
    expect(taps, 0);
    await tester.tap(find.text('Account'));
    expect(taps, 1);
    await press(tester, LogicalKeyboardKey.tab);
    await press(tester, LogicalKeyboardKey.tab);
    await press(tester, LogicalKeyboardKey.enter);
    expect(actions, 2);
    expect(taps, 1);
  });
  testWidgets('public row selects platform', (tester) async {
    await pumpApp(tester, const ZenListRow(title: 'Account'));
    expect(find.byType(zenIsApplePlatform ? CupertinoListTile : ListTile), findsOneWidget);
  });
}
