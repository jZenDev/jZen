import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_store/zen_ui_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

final _key = List<int>.generate(32, (i) => (i * 5 + 9) & 255);
final _start = DateTime.utc(2026, 11, 14, 10);

Widget _app(Widget home, {String locale = 'en', ThemeData? theme}) => MaterialApp(
  locale: Locale(locale),
  theme: theme,
  localizationsDelegates: const [
    storeLocaleDelegate,
    zenWidgetsLocaleDelegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: const [Locale('en'), Locale('uk')],
  home: home,
);

void main() {
  group('Add a device', () {
    late DateTime clock;
    var closed = 0;
    setUp(() {
      clock = _start;
      closed = 0;
    });

    Future<void> open(WidgetTester tester, {String locale = 'en'}) async {
      await tester.pumpWidget(
        _app(
          ZenAddDeviceScreen(syncKey: _key, onClose: () => closed++, now: () => clock),
          locale: locale,
        ),
      );
    }

    testWidgets('shows no code until the person asks', (tester) async {
      await open(tester);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.byType(ZenPairingCodeView), findsNothing);
      await tester.tap(find.text('Show Code'));
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('Valid for 5:00'), findsOneWidget);
    });

    testWidgets('the code shown joins a device holding no key', (tester) async {
      await open(tester);
      await tester.tap(find.text('Show Code'));
      await tester.pump();
      final shown = tester.widget<ZenPairingCodeView>(find.byType(ZenPairingCodeView));
      expect(ZenPairing.accept(shown.qrData, now: clock).dataOrNull, _key);
      expect(ZenPairing.accept(shown.text, now: clock).dataOrNull, _key);
    });

    testWidgets('counts down and withdraws the code at expiry', (tester) async {
      await open(tester);
      await tester.tap(find.text('Show Code'));
      await tester.pump();
      clock = _start.add(const Duration(minutes: 2, seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Valid for 2:30'), findsOneWidget);

      clock = _start.add(const Duration(minutes: 6));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ZenPairingCodeView), findsNothing);
      expect(find.textContaining('expired'), findsOneWidget);
      expect(find.text('Show a New Code'), findsOneWidget);

      await tester.tap(find.text('Show a New Code'));
      await tester.pump();
      expect(find.byType(ZenPairingCodeView), findsOneWidget);
    });

    testWidgets('hides the code when the app leaves the screen', (tester) async {
      await open(tester);
      await tester.tap(find.text('Show Code'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.byType(ZenPairingCodeView), findsNothing);
      expect(find.textContaining('hidden'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('cancel closes, and nothing is put on the clipboard or in a long press', (
      tester,
    ) async {
      final clipboardWrites = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') clipboardWrites.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await open(tester);
      await tester.tap(find.text('Show Code'));
      await tester.pump();
      expect(find.byType(SelectableText), findsNothing);
      expect(find.byType(SelectionArea), findsNothing);
      await tester.scrollUntilVisible(find.text('Cancel'), 200);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      expect(closed, 1);
      expect(clipboardWrites, isEmpty);
    });

    testWidgets('speaks Ukrainian', (tester) async {
      await open(tester, locale: 'uk');
      expect(find.text('Додати пристрій'), findsWidgets);
      expect(find.text('Показати код'), findsOneWidget);
    });
  });

  group('Join', () {
    final goodCode = ZenPairing.offer(_key, now: _start);
    late List<List<int>> received;
    ZenResult<void> storeResult = const ZenSuccess(null);
    var cancelled = 0;
    var clock = _start;

    setUp(() {
      received = [];
      storeResult = const ZenSuccess(null);
      cancelled = 0;
      clock = _start;
    });

    Future<void> open(WidgetTester tester, {ZenQrScannerBuilder? scanner}) async {
      await tester.pumpWidget(
        _app(
          ZenJoinScreen(
            onKey: (key) async {
              received.add(key);
              return storeResult;
            },
            onCancel: () => cancelled++,
            scanner: scanner,
            now: () => clock,
          ),
        ),
      );
    }

    Future<void> typeAndJoin(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(EditableText), text);
      await tester.tap(find.widgetWithText(ZenButton, 'Join'));
      await tester.pumpAndSettle();
    }

    testWidgets('a typed code hands over the key', (tester) async {
      await open(tester);
      await typeAndJoin(tester, goodCode.text.toLowerCase());
      expect(received, [_key]);
      expect(find.textContaining('mistake'), findsNothing);
    });

    testWidgets('the field hides what is typed', (tester) async {
      await open(tester);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      // A hidden field is a password-type input on every platform, which is what stops a
      // keyboard learning the code or offering it back; ZenTextField has no flag of its own.
      expect(field.obscureText, isTrue);
    });

    testWidgets('a mistyped character names its group and hands over nothing', (tester) async {
      await open(tester);
      final text = goodCode.text;
      final broken = text.replaceRange(
        8,
        9,
        text[8] == 'A' ? 'B' : 'A',
      ); // second group's first character
      await typeAndJoin(tester, broken);
      expect(find.textContaining('Group 2 has a mistake'), findsOneWidget);
      expect(received, isEmpty);
    });

    testWidgets('an incomplete code says how long a code is', (tester) async {
      await open(tester);
      await typeAndJoin(tester, goodCode.text.substring(0, 20));
      expect(find.textContaining('11 groups of 7'), findsOneWidget);
      expect(received, isEmpty);
    });

    testWidgets('an expired code is refused', (tester) async {
      await open(tester);
      clock = _start.add(const Duration(minutes: 10));
      await typeAndJoin(tester, goodCode.text);
      expect(find.textContaining('has expired'), findsOneWidget);
      expect(received, isEmpty);
    });

    testWidgets('a failure to keep the key is shown, and the code stays to retry', (tester) async {
      storeResult = const ZenFailure(ZenStorageError('the keychain is locked'));
      await open(tester);
      await typeAndJoin(tester, goodCode.text);
      expect(find.textContaining('the keychain is locked'), findsOneWidget);
      expect(received, hasLength(1));
    });

    testWidgets('cancel closes', (tester) async {
      await open(tester);
      await tester.tap(find.text('Cancel'));
      expect(cancelled, 1);
    });

    testWidgets('no camera button without a scanner; a scan joins like typing', (tester) async {
      await open(tester);
      expect(find.text('Scan with Camera'), findsNothing);

      late ValueChanged<String> scanned;
      await open(
        tester,
        scanner: (context, onCode) {
          scanned = onCode;
          return const SizedBox(key: Key('camera'));
        },
      );
      await tester.tap(find.text('Scan with Camera'));
      await tester.pump();
      expect(find.byKey(const Key('camera')), findsOneWidget);
      scanned(goodCode.qrData);
      await tester.pumpAndSettle();
      expect(received, [_key]);
    });

    testWidgets('a scanned code that is not ours is refused', (tester) async {
      late ValueChanged<String> scanned;
      await open(
        tester,
        scanner: (context, onCode) {
          scanned = onCode;
          return const SizedBox();
        },
      );
      await tester.tap(find.text('Scan with Camera'));
      await tester.pump();
      scanned('https://example.com/menu');
      await tester.pumpAndSettle();
      expect(received, isEmpty);
      // Back at the typed field, which says what was wrong rather than scanning on.
      expect(find.text('Scan with Camera'), findsOneWidget);
      expect(find.textContaining('only digits and letters'), findsOneWidget);
    });

    testWidgets('speaks Ukrainian', (tester) async {
      await tester.pumpWidget(
        _app(
          ZenJoinScreen(onKey: (_) async => const ZenSuccess(null), onCancel: () {}),
          locale: 'uk',
        ),
      );
      expect(find.text('Приєднатися'), findsWidgets);
    });
  });

  group('accessibility', () {
    final themes = {
      for (final b in Brightness.values)
        b.name: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: b),
        ),
    };

    for (final entry in themes.entries) {
      testWidgets('Add a device meets contrast, target size and naming (${entry.key})', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            ZenAddDeviceScreen(syncKey: _key, onClose: () {}, now: () => _start),
            theme: entry.value,
          ),
        );
        await tester.tap(find.text('Show Code'));
        await tester.pump();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(find.bySemanticsLabel(RegExp('Pairing code')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('QR code')), findsOneWidget);
        handle.dispose();
      });

      testWidgets('Join meets contrast, target size and naming (${entry.key})', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            ZenJoinScreen(
              onKey: (_) async => const ZenSuccess(null),
              onCancel: () {},
              scanner: (context, onCode) => const SizedBox(),
            ),
            theme: entry.value,
          ),
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }

    testWidgets('both screens lay out at 200% text on a phone', (tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _app(ZenAddDeviceScreen(syncKey: _key, onClose: () {}, now: () => _start)),
        ),
      );
      await tester.scrollUntilVisible(find.text('Show Code'), 200);
      await tester.ensureVisible(find.text('Show Code'));
      await tester.tap(find.text('Show Code'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _app(
            ZenJoinScreen(
              onKey: (_) async => const ZenSuccess(null),
              onCancel: () {},
              scanner: (context, onCode) => const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
