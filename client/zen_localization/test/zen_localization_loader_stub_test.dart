// Ported from
// ../DartZen/packages/dartzen_localization/test/zen_localization_loader_stub_test.dart.
import 'package:test/test.dart';
import 'package:zen_localization/src/loader/loader_stub.dart';

void main() {
  group('ZenLocalizationLoaderStub', () {
    test('throws UnsupportedError on load', () async {
      final loader = ZenLocalizationLoaderStub();
      expect(() => loader.load('foo'), throwsA(isA<UnsupportedError>()));
    });

    test('getLoader returns ZenLocalizationLoaderStub', () {
      final loader = getLoader();
      expect(loader, isA<ZenLocalizationLoaderStub>());
    });
  });
}
