import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

// The native keychain cannot run in a host test, so this pins which options each build compiles in.
void main() {
  test('a non-release dev build uses the file keychain, which needs no signing identity', () {
    final options = ZenSecureLockStorage.macOsOptions(dev: true).toMap();

    expect(options['usesDataProtectionKeychain'], 'false');
  });

  test('every other build (prd, and a release build made with ZEN_ENV=dev) keeps the data-protection keychain, first_unlock_this_device', () {
    final options = ZenSecureLockStorage.macOsOptions(dev: false).toMap();

    expect(options['usesDataProtectionKeychain'], 'true');
    expect(options['accessibility'], 'first_unlock_this_device');
  });

  test('the default storage takes the choice from zenIsDevBuild, which a release build never is', () {
    expect(
      ZenSecureLockStorage().storage.mOptions.toMap(),
      ZenSecureLockStorage.macOsOptions(dev: zenIsDevBuild).toMap(),
    );
  });
}
