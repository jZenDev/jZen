import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_demo_client/src/providers.dart';
import 'package:zen_demo_client/src/shared_preferences_locale_store.dart';

/// The language picker's choice must outlive the process. A "restart" here is a new
/// [ProviderContainer] over the same storage, which is exactly what a relaunch is: nothing of the
/// old container survives, only what was written to the device.
void main() {
  Future<ProviderContainer> launch({
    List<String> device = const ['en-US'],
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        deviceLanguagesProvider.overrideWithValue(device),
        localePreferenceProvider.overrideWithValue(
          ZenLocalePreference(
            supported: demoSupportedLocales,
            store: SharedPreferencesLocaleStore(preferences),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a language chosen in the picker is still chosen after a restart', () async {
    final first = await launch();
    expect(first.read(localeProvider), const Locale(ZenLocales.en));

    await first.read(localeProvider.notifier).setLocale(const Locale(ZenLocales.uk));
    expect(first.read(localeProvider), const Locale(ZenLocales.uk));

    final second = await launch();
    expect(second.read(localeProvider), const Locale(ZenLocales.uk));
  });

  test('on first launch the device language is used when it is supported', () async {
    final container = await launch(device: const ['de-DE', 'uk-UA']);
    expect(container.read(localeProvider), const Locale(ZenLocales.uk));
  });

  test('on first launch an unsupported device language gives the fallback', () async {
    final container = await launch(device: const ['de-DE']);
    expect(container.read(localeProvider), const Locale(ZenLocales.fallback));
  });

  test('a stored choice wins over the device language', () async {
    SharedPreferences.setMockInitialValues({SharedPreferencesLocaleStore.key: 'en'});
    final container = await launch(device: const ['uk']);
    expect(container.read(localeProvider), const Locale(ZenLocales.en));
  });

  test('a stored tag that is no longer supported falls back instead of throwing', () async {
    SharedPreferences.setMockInitialValues({SharedPreferencesLocaleStore.key: 'pl'});
    final container = await launch(device: const ['de']);
    expect(container.read(localeProvider), const Locale(ZenLocales.fallback));
  });

  test('an unsupported language is refused and changes nothing', () async {
    final container = await launch();
    await expectLater(
      container.read(localeProvider.notifier).setLocale(const Locale('de')),
      throwsArgumentError,
    );
    expect(container.read(localeProvider), const Locale(ZenLocales.en));
    expect((await SharedPreferences.getInstance()).getString(SharedPreferencesLocaleStore.key), isNull);
  });
}
