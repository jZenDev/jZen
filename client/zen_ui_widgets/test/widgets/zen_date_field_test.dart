import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/src/zen_date_field.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing, ZenDateField, ZenDateRangeField;

import '../support/a11y.dart';

final DateTime first = DateTime(2025, 1, 1);
final DateTime last = DateTime(2025, 12, 31);

/// A date field whose value the test owns, as an app's would be.
class Host extends StatefulWidget {
  const Host({this.initial, this.clearable = false, super.key});

  final DateTime? initial;
  final bool clearable;

  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  DateTime? value;

  @override
  void initState() {
    super.initState();
    value = widget.initial;
  }

  @override
  Widget build(BuildContext context) => ZenDateField(
    label: 'Due date',
    value: value,
    firstDate: first,
    lastDate: last,
    clearable: widget.clearable,
    onChanged: (DateTime? d) => setState(() => value = d),
  );
}

class RangeHost extends StatefulWidget {
  const RangeHost({this.from, this.to, super.key});

  final DateTime? from;
  final DateTime? to;

  @override
  State<RangeHost> createState() => RangeHostState();
}

class RangeHostState extends State<RangeHost> {
  DateTime? from;
  DateTime? to;

  @override
  void initState() {
    super.initState();
    from = widget.from;
    to = widget.to;
  }

  @override
  Widget build(BuildContext context) => ZenDateRangeField(
    fromLabel: 'From',
    toLabel: 'To',
    from: from,
    to: to,
    firstDate: first,
    lastDate: last,
    onChanged: (DateTime? f, DateTime? t) => setState(() {
      from = f;
      to = t;
    }),
  );
}

/// The public field opens the wheel on iOS, so tests that drive Material's calendar dialog through
/// it only apply to the other builds; the wheel has its own test below, calling it directly.
const bool materialOnly = zenIsIOS;

void main() {
  group('ZenDateField (Material picker)', () {
    testWidgets('is one control: label and date together, a button', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, Host(initial: DateTime(2025, 3, 14)));

      final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.tap);
      expect(nodes, hasLength(1), reason: nodes.map((n) => n.label).join(' | '));
      expect(nodes.single.label, contains('Due date'));
      expect(nodes.single.label, contains('Mar 14, 2025'));
      expect(occurrences(nodes.single.label, 'Due date'), 1, reason: nodes.single.label);
      expect(nodes.single.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('an empty field says so, in words', (tester) async {
      await pumpApp(tester, const Host());
      expect(find.text('Select a date'), findsOneWidget);
    });

    testWidgets('picking reports a date-only value', (tester) async {
      await pumpApp(tester, Host(initial: DateTime(2025, 3, 14, 17, 45)));
      await tester.tap(find.text('Due date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Mar 20, 2025'), findsOneWidget);
    }, skip: materialOnly);

    testWidgets('an initial value outside the bounds opens at the nearest bound', (tester) async {
      await pumpApp(tester, Host(initial: DateTime(2030, 6, 1)));
      await tester.tap(find.byType(ZenDateField));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    }, skip: materialOnly);

    testWidgets(
      'Tab, Enter opens the picker and a ring shows',
      (tester) async {
        await pumpApp(tester, Host(initial: DateTime(2025, 3, 14)));
        await press(tester, LogicalKeyboardKey.tab);
        expect(isRinged(tester, find.byType(FocusRing)), isTrue);
        await press(tester, LogicalKeyboardKey.enter);
        expect(find.byType(DatePickerDialog), findsOneWidget);
      },
      semanticsEnabled: false,
      skip: materialOnly,
    );

    testWidgets('clearable: a separate, named button empties it', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, Host(initial: DateTime(2025, 3, 14), clearable: true));

      final List<SemanticsData> nodes = nodesWith(tester, SemanticsAction.tap);
      expect(nodes, hasLength(2), reason: nodes.map((n) => n.label).join(' | '));
      // The name of an icon-only button is its tooltip, which Flutter exposes on the node.
      expect(nodes.where((SemanticsData d) => d.tooltip == 'Clear date'), hasLength(1));

      await tester.tap(find.byTooltip('Clear date'));
      await tester.pumpAndSettle();
      expect(find.text('Select a date'), findsOneWidget);
      expect(find.byTooltip('Clear date'), findsNothing, reason: 'nothing left to clear');
      handle.dispose();
    });

    testWidgets('names itself in Ukrainian', (tester) async {
      await pumpApp(tester, const Host(clearable: true), locale: const Locale('uk'));
      expect(find.text('Оберіть дату'), findsOneWidget);
    });
  });

  group('ZenDateField (iOS wheel)', () {
    testWidgets('Done commits the wheel, dismissing does not', (tester) async {
      DateTime? picked;
      await pumpApp(
        tester,
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async => picked = await pickCupertinoDate(
              context,
              initial: DateTime(2025, 3, 14),
              first: first,
              last: last,
            ),
            child: const Text('Open'),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(picked, isNull);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(picked, DateTime(2025, 3, 14));
    });
  });

  group('ZenDateRangeField', () {
    testWidgets('the start picker cannot go past the end, the end cannot precede the start', (
      tester,
    ) async {
      await pumpApp(tester, RangeHost(from: DateTime(2025, 3, 10), to: DateTime(2025, 3, 20)));

      await tester.tap(find.text('From'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker)).lastDate,
        DateTime(2025, 3, 20),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('To'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker)).firstDate,
        DateTime(2025, 3, 10),
      );
    }, skip: materialOnly);

    testWidgets('an open end keeps the full bounds', (tester) async {
      await pumpApp(tester, RangeHost(from: DateTime(2025, 3, 10)));
      await tester.tap(find.text('From'));
      await tester.pumpAndSettle();
      expect(tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker)).lastDate, last);
    }, skip: materialOnly);

    testWidgets('an inverted pair handed in is reported, in words, under the end', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpApp(tester, RangeHost(from: DateTime(2025, 6, 1), to: DateTime(2025, 5, 1)));
      expect(find.text('The start date must not be after the end date'), findsOneWidget);
      final SemanticsData end = nodesWith(
        tester,
        SemanticsAction.tap,
      ).firstWhere((SemanticsData d) => d.label.contains('To'));
      expect(end.label, contains('must not be after'));
      handle.dispose();
    });

    testWidgets('a valid pair shows no error', (tester) async {
      await pumpApp(tester, RangeHost(from: DateTime(2025, 5, 1), to: DateTime(2025, 5, 1)));
      expect(find.textContaining('must not be after'), findsNothing);
    });

    testWidgets('stacks the two fields at 200% text on a narrow screen', (tester) async {
      await pumpApp(
        tester,
        RangeHost(from: DateTime(2025, 5, 1), to: DateTime(2025, 5, 9)),
        size: const Size(320, 800),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('To')).dy,
        greaterThan(tester.getBottomLeft(find.text('From')).dy),
      );
    });

    for (final MapEntry<String, ThemeData> theme in auditThemes.entries) {
      testWidgets('meets AA text contrast (${theme.key})', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpApp(
          tester,
          RangeHost(from: DateTime(2025, 6, 1), to: DateTime(2025, 5, 1)),
          theme: theme.value,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });
}
