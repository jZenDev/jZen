import 'package:zen_core/zen_core.dart';
import 'package:zen_localization/zen_localization.dart'; // Added import
import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ZenNavigation renders body content',
      (WidgetTester tester) async {
    // ZenNavigation selects platform builders and is not implemented on web.
    if (zenIsWeb) return;
    const config = ZenLocalizationConfig();
    final service = ZenLocalizationService(config: config);
    var selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, setState) => ZenNavigation(
            selectedIndex: selectedIndex,
            onItemSelected: (index) {
              setState(() {
                selectedIndex = index;
              });
            },
            localization: service,
            language: 'en',
            items: [
              ZenNavigationItem(
                id: 'tab1',
                label: 'Tab 1',
                icon: Icons.home,
                builder: (context) => const Text('Content Tab 1'),
              ),
              ZenNavigationItem(
                id: 'tab2',
                label: 'Tab 2',
                icon: Icons.settings,
                builder: (context) => const Text('Content Tab 2'),
              ),
            ],
          ),
        ),
      ),
    );

    // Initial state: Tab 1 content should be visible
    expect(find.text('Content Tab 1'), findsOneWidget);
    expect(find.text('Content Tab 2'), findsNothing);

    // Tap on Tab 2
    await tester.tap(find.text('Tab 2'));
    await tester.pump();

    // After tap: Tab 2 content should be visible
    expect(find.text('Content Tab 1'), findsNothing);
    expect(find.text('Content Tab 2'), findsOneWidget);
  });
}
