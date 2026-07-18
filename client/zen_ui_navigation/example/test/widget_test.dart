import 'package:zen_ui_navigation_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('NavigationExampleApp app builds and shows navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: NavigationExampleApp()),
    );
    await tester.pumpAndSettle();

    // Verify the app builds without errors
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(AdaptiveNavigationShell), findsOneWidget);
  });

  testWidgets('AdaptiveNavigationShell renders navigation items', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: NavigationExampleApp()),
    );
    await tester.pumpAndSettle();

    // Verify navigation is rendered
    expect(find.byType(AdaptiveNavigationShell), findsOneWidget);
  });
}
