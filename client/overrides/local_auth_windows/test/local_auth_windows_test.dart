import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:local_auth_windows/local_auth_windows.dart';

void main() {
  test('Windows says the device cannot check its owner, so the PIN is reset by erasing', () async {
    LocalAuthWindows.registerWith();
    final auth = LocalAuthPlatform.instance;

    expect(auth, isA<LocalAuthWindows>());
    expect(await auth.isDeviceSupported(), isFalse);
    expect(await auth.deviceSupportsBiometrics(), isFalse);
    expect(await auth.getEnrolledBiometrics(), isEmpty);
    expect(
      auth.authenticate(localizedReason: 'x', authMessages: const []),
      throwsA(isA<LocalAuthException>()),
    );
  });

  test('local_auth can name the Windows messages type it defaults to', () {
    expect(const WindowsAuthMessages().args, isEmpty);
  });
}
