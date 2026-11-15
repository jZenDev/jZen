import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

export 'package:local_auth_platform_interface/types/auth_messages.dart';
export 'package:local_auth_platform_interface/types/auth_options.dart';
export 'package:local_auth_platform_interface/types/biometric_type.dart';

/// A Windows `local_auth` that has no native code and says the device cannot check its owner.
///
/// The pub.dev `local_auth_windows` (2.0.2, the latest) compiles with `/await`, which Visual
/// Studio 18's MSVC refuses (error STL1011), so no Windows build that depends on `local_auth`
/// links. Until a fixed release exists jZen overrides it with this (ADR-081). `zen_ui_lock` reads
/// `isDeviceSupported() == false` as "no owner check" and offers erasing this device's copy
/// instead, exactly as it does on Linux.
class LocalAuthWindows extends LocalAuthPlatform {
  /// Registers this as the Windows implementation; Flutter calls it at start-up.
  static void registerWith() {
    LocalAuthPlatform.instance = LocalAuthWindows();
  }

  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<bool> deviceSupportsBiometrics() async => false;

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async => const <BiometricType>[];

  @override
  Future<bool> stopAuthentication() async => false;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async => throw const LocalAuthException(code: LocalAuthExceptionCode.noBiometricHardware);
}
