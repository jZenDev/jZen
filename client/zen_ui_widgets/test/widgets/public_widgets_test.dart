import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../support/a11y.dart';

/// The public widgets choose their idiom on compile-time constants, so this suite renders whichever
/// branch the host build (`ZEN_PLATFORM`) selected, end to end, with no error.
void main() {
  testWidgets('every public control builds and operates on this platform', (tester) async {
    bool on = false;
    Kind kind = Kind.a;
    String? currency;
    DateTime? day;
    final TextEditingController amount = TextEditingController();
    addTearDown(amount.dispose);

    await pumpApp(
      tester,
      StatefulBuilder(
        builder: (BuildContext context, StateSetter set) => Column(
          children: <Widget>[
            ZenButton(label: 'Save', onPressed: () {}),
            ZenButton(label: 'Back', onPressed: () {}, variant: ZenButtonVariant.secondary),
            ZenButton(label: 'Skip', onPressed: () {}, variant: ZenButtonVariant.text),
            ZenIconButton(icon: Icons.logout, label: 'Log out', onPressed: () {}),
            ZenSwitchRow(label: 'Archived', value: on, onChanged: (bool v) => set(() => on = v)),
            ZenSegmentedControl<Kind>(
              segments: const <ZenSegment<Kind>>[
                ZenSegment<Kind>(value: Kind.a, label: 'A'),
                ZenSegment<Kind>(value: Kind.b, label: 'B'),
              ],
              selected: kind,
              onChanged: (Kind k) => set(() => kind = k),
            ),
            ZenSelect<String>(
              label: 'Currency',
              items: const <String>['EUR', 'UAH'],
              itemLabel: (String c) => c,
              value: currency,
              onChanged: (String c) => set(() => currency = c),
            ),
            ZenDateField(label: 'Due', value: day, onChanged: (DateTime? d) => set(() => day = d)),
            ZenAmountField(label: 'Amount', controller: amount, maxFractionDigits: 2),
          ],
        ),
      ),
      size: const Size(800, 1400),
    );

    await tester.tap(find.text('Archived'));
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(on, isTrue);
    expect(kind, Kind.b);

    await tester.enterText(find.byType(EditableText).last, '1.23');
    await tester.enterText(find.byType(EditableText).last, '1.234');
    expect(amount.text.replaceAll(',', '.'), '1.23', reason: 'a third fractional digit is refused');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a page and a message build and operate on this platform', (tester) async {
    int undone = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => ZenPageScaffold(
            title: 'Profile',
            actions: <Widget>[
              ZenIconButton(
                icon: Icons.logout,
                label: 'Log out',
                badge: 2,
                onPressed: () => showZenMessage(
                  context,
                  'Signed out',
                  actionLabel: 'Undo',
                  onAction: () => undone++,
                ),
              ),
            ],
            body: const Column(
              children: <Widget>[
                ZenProgressBar(value: 0.4, label: 'Goal'),
                ZenTextField(label: 'Note', minLines: 2, maxLines: 4, maxLength: 80),
                ListTile(title: Text('Body')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('0/80'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('Signed out'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

enum Kind { a, b }
