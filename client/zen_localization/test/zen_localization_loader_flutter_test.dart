// Ported from
// ../DartZen/packages/dartzen_localization/test/zen_localization_loader_flutter_test.dart.
// Runs under `flutter test` (needs a Flutter binding); flutter_test is a dev dependency.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_localization/src/loader/loader_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ZenLocalizationLoaderFlutter', () {
    testWidgets('loads string from rootBundle', (tester) async {
      const testKey = 'assets/test.json';
      const testContent = '{"foo": "bar"}';
      // Register fake asset
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            final String key = const StringCodec().decodeMessage(message)!;
            if (key == testKey) {
              return const StringCodec().encodeMessage(testContent);
            }
            return null;
          });
      final loader = ZenLocalizationLoaderFlutter();
      final content = await loader.load(testKey);
      expect(content, testContent);
    });

    testWidgets('throws if asset missing', (tester) async {
      final loader = ZenLocalizationLoaderFlutter();
      expect(() => loader.load('missing.json'), throwsA(isA<dynamic>()));
    });

    test('getLoader returns ZenLocalizationLoaderFlutter', () {
      final loader = getLoader();
      expect(loader, isA<ZenLocalizationLoaderFlutter>());
    });
  });
}
