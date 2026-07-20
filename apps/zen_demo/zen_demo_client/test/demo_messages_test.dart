import 'package:flutter_test/flutter_test.dart';
import 'package:zen_localization/zen_localization.dart';

import 'package:zen_demo_client/src/demo_messages.dart';

/// Loads the real merged bundles (assets/l10n/{en,uk}.json) through the localization service and
/// asserts the demo keys resolve and interpolate, and that en and uk actually differ. This is the
/// same production-mode path the app uses, so it catches a JSON typo or a missing key before the
/// UI or the e2e run would. Mirrors DartZen's client_messages_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ZenLocalizationService service;

  setUp(() async {
    service = ZenLocalizationService(
      config: const ZenLocalizationConfig(globalPath: 'assets/l10n'),
    );
    await service.loadGlobalMessages('en');
    await service.loadGlobalMessages('uk');
  });

  test('demo keys resolve in English', () {
    final messages = DemoMessages(service, 'en');
    expect(messages.appTitle, 'jZen Demo');
    expect(messages.pingJson, 'Ping (JSON)');
    expect(messages.navProfile, 'Profile');
  });

  test('demo keys resolve in Ukrainian and differ from English', () {
    final en = DemoMessages(service, 'en');
    final uk = DemoMessages(service, 'uk');
    expect(uk.appTitle, isNot(equals(en.appTitle)));
    expect(uk.pingSection, isNot(equals(en.pingSection)));
    expect(uk.appTitle, isNotEmpty);
  });

  test('interpolation fills named params', () {
    final messages = DemoMessages(service, 'en');
    expect(messages.pingResult('json', 'Server is alive'), 'json: Server is alive');
    expect(messages.wsStatus('connected'), 'Status: connected');
  });
}
