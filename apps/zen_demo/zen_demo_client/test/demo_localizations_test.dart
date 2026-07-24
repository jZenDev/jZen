import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_demo_client/src/l10n/generated/demo_localizations.dart';
import 'package:zen_demo_client/src/providers.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

/// The typed replacement for demo_messages_test.dart (ROADMAP step 7b, ADR-009).
///
/// The old test loaded the merged assets/l10n bundles to catch a JSON typo or a missing key.
/// Neither failure exists any more: the app has no bundle to load, and a missing key does not
/// compile. What is worth asserting is what survived the change - that both locales carry real
/// wording, that placeholders still interpolate, and that the one wiring this app owns (the
/// locale that both re-renders the UI and travels as Accept-Language) does both jobs.
void main() {
  Future<DemoLocalizations> messages(String locale) =>
      DemoLocalizations.delegate.load(Locale(locale));

  test('ships exactly the locales ZenLocales declares', () {
    expect(DemoLocalizations.supportedLocales.map((l) => l.languageCode), ZenLocales.supported);
  });

  test('demo strings resolve in English', () async {
    final en = await messages(ZenLocales.en);
    expect(en.appTitle, 'jZen Demo');
    expect(en.pingJson, 'Ping (JSON)');
    expect(en.navProfile, 'Profile');
  });

  test('demo strings resolve in Ukrainian and differ from English', () async {
    final en = await messages(ZenLocales.en);
    final uk = await messages(ZenLocales.uk);
    expect(uk.appTitle, isNot(equals(en.appTitle)));
    expect(uk.pingSection, isNot(equals(en.pingSection)));
    expect(uk.appTitle, isNotEmpty);
  });

  test('placeholders interpolate', () async {
    final en = await messages(ZenLocales.en);
    expect(en.pingResult('json', 'Server is alive'), 'json: Server is alive');
    expect(en.wsStatus('connected'), 'Status: connected');
  });

  test('the locale provider starts at the framework fallback', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(localeProvider), const Locale(ZenLocales.fallback));
    expect(container.read(localeProvider).languageCode, ZenLocales.en);
  });

  test('switching the locale is what ZenClient will read as Accept-Language', () {
    // The exact expression main.dart hands ZenClient as its `language` callback (ADR-007).
    final container = ProviderContainer();
    addTearDown(container.dispose);
    String acceptLanguage() => container.read(localeProvider).languageCode;

    expect(acceptLanguage(), ZenLocales.en);
    container.read(localeProvider.notifier).setLocale(const Locale(ZenLocales.uk));
    expect(acceptLanguage(), ZenLocales.uk);
  });

  testWidgets('one locale change re-renders the app and both framework packages', (tester) async {
    // Three delegates, three packages, one Locale: the composition ADR-009 chose.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: ref.watch(localeProvider),
            localizationsDelegates: const [
              ...DemoLocalizations.localizationsDelegates,
              IdentityLocalizations.delegate,
              NavigationLocalizations.delegate,
            ],
            supportedLocales: DemoLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Column(
                children: [
                  Text(DemoLocalizations.of(context).navTerms),
                  Text(IdentityLocalizations.of(context).profileTitle),
                  Text(NavigationLocalizations.of(context).more),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Terms'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    container.read(localeProvider.notifier).setLocale(const Locale(ZenLocales.uk));
    await tester.pumpAndSettle();

    expect(find.text('Умови'), findsOneWidget);
    expect(find.text('Профіль'), findsOneWidget);
    expect(find.text('Ще'), findsOneWidget);
    expect(find.text('Terms'), findsNothing);

    // And the same switch is what the next request will carry.
    expect(container.read(localeProvider).languageCode, ZenLocales.uk);
  });
}
