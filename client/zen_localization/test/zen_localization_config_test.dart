// Ported from
// ../DartZen/packages/dartzen_localization/test/zen_localization_config_test.dart.
import 'package:test/test.dart';
import 'package:zen_localization/src/zen_localization_config.dart';

void main() {
  group('ZenLocalizationConfig', () {
    test('default values', () {
      const config = ZenLocalizationConfig();
      expect(config.globalPath, 'assets/l10n');
      expect(config.isProduction, true);
    });

    test('custom values', () {
      const config = ZenLocalizationConfig(
        globalPath: 'foo/bar',
        isProduction: false,
      );
      expect(config.globalPath, 'foo/bar');
      expect(config.isProduction, false);
    });
  });
}
