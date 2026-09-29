// The dispatch is on compile-time constants, so this asserts the one branch the host platform
// this run was compiled for (`task test:client` passes ZEN_PLATFORM), against the constants
// themselves. `presenters_test.dart` covers the four presentations.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

void main() {
  testWidgets('shows a presentation that matches the platform constants', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () =>
                showAdaptivePresentation<void>(context, builder: (_) => const Text('content')),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('content'), findsOneWidget);
    expect(
      find.byType(BottomSheet),
      zenIsMobile && !zenIsApplePlatform ? findsOneWidget : findsNothing,
    );
    expect(
      find.byType(Dialog),
      !zenIsMobile && !zenIsApplePlatform ? findsOneWidget : findsNothing,
    );
    expect(
      find.byType(CupertinoPopupSurface),
      !zenIsMobile && zenIsApplePlatform ? findsOneWidget : findsNothing,
    );
  });
}
