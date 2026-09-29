// Each presenter is exercised directly. The public entry point picks one on compile-time
// constants, so a single test run only ever reaches the branch of the host platform it was
// compiled for; calling the four presenters covers every idiom on every host.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/src/presenters.dart';

typedef Presenter =
    Future<Object?> Function(BuildContext context, WidgetBuilder builder, bool barrierDismissible);

/// Pumps an app with one button that opens [present]ed content, and returns the future's result
/// holder so a test can read what the overlay closed with.
Future<List<Object?>> _open(
  WidgetTester tester,
  Presenter present, {
  bool dismissible = true,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final List<Object?> result = <Object?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => present(
            context,
            (BuildContext context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const TextField(key: Key('field')),
                TextButton(
                  onPressed: () => Navigator.of(context).pop('done'),
                  child: const Text('Save'),
                ),
              ],
            ),
            dismissible,
          ).then(result.add),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  final Map<String, Presenter> presenters = <String, Presenter>{
    'material sheet': presentMaterialSheet<Object?>,
    'cupertino sheet': presentCupertinoSheet<Object?>,
    'material dialog': presentMaterialDialog<Object?>,
    'cupertino dialog': presentCupertinoDialog<Object?>,
  };

  for (final MapEntry<String, Presenter> entry in presenters.entries) {
    group(entry.key, () {
      testWidgets('shows the content, with a working Material text field', (tester) async {
        await _open(tester, entry.value);

        expect(find.text('Save'), findsOneWidget);
        // A TextField throws without a Material ancestor, so getting here proves the surface.
        await tester.enterText(find.byKey(const Key('field')), 'hello');
        expect(find.text('hello'), findsOneWidget);
      });

      testWidgets('completes with the value the content pops', (tester) async {
        final List<Object?> result = await _open(tester, entry.value);

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(find.text('Save'), findsNothing);
        expect(result, <Object?>['done']);
      });
    });
  }

  group('dismissal', () {
    testWidgets('a dialog closes on a tap outside, with null', (tester) async {
      final List<Object?> result = await _open(tester, presentMaterialDialog<Object?>);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsNothing);
      expect(result, <Object?>[null]);
    });

    testWidgets('barrierDismissible: false keeps a dialog open on a tap outside', (tester) async {
      await _open(tester, presentMaterialDialog<Object?>, dismissible: false);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('barrierDismissible: false keeps a Cupertino dialog open', (tester) async {
      await _open(tester, presentCupertinoDialog<Object?>, dismissible: false);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
    });
  });

  group('dialog size', () {
    testWidgets('a Material dialog never grows past the maximum width', (tester) async {
      await _open(tester, presentMaterialDialog<Object?>);

      expect(tester.getSize(find.byType(Column)).width, lessThanOrEqualTo(zenDialogMaxWidth));
    });

    testWidgets('a Cupertino dialog never grows past the maximum width', (tester) async {
      await _open(tester, presentCupertinoDialog<Object?>);

      expect(
        tester.getSize(find.byType(CupertinoPopupSurface)).width,
        lessThanOrEqualTo(zenDialogMaxWidth),
      );
    });
  });

  testWidgets('a Material sheet fills the height of the screen', (tester) async {
    await _open(tester, presentMaterialSheet<Object?>);

    expect(tester.getSize(find.byType(BottomSheet)).height, 900);
  });
}
