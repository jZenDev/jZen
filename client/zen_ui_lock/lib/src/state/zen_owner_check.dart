import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zen_core/zen_core.dart';

/// Confirms that the person holding the device is its owner, for resetting a forgotten PIN.
abstract interface class ZenOwnerCheck {
  /// Whether this device can check its owner at all. False on Linux, where `local_auth` has no
  /// implementation, and on a device with no passcode or Windows Hello set up. "Forgot PIN?" then
  /// offers erasing this device's copy instead (ADR-075) — never a bare reset, which would hand
  /// the data to whoever holds the device.
  Future<bool> isAvailable();

  /// Asks for the device's own authentication, telling the person [reason]. Succeeds only when
  /// they pass it.
  Future<ZenResult<void>> confirm(String reason);
}

/// The default [ZenOwnerCheck]: the device passcode, Face ID or Touch ID, whichever the owner has
/// set up. Biometrics alone are not required, so an owner without them can still recover.
final class ZenDeviceOwnerCheck implements ZenOwnerCheck {
  final LocalAuthentication _auth;

  /// Uses [auth], or the platform's.
  ZenDeviceOwnerCheck({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    // `local_auth` registers nothing on Linux; asking would throw MissingPluginException.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) return false;
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      // Any failure to ask is "cannot check the owner": the person is then offered the erase
      // path, which exposes nothing, rather than a reset that would.
      return false;
    }
  }

  @override
  Future<ZenResult<void>> confirm(String reason) async {
    try {
      final passed = await _auth.authenticate(localizedReason: reason);
      return passed
          ? const ZenResult.ok(null)
          : const ZenResult.err(ZenUnauthorizedError('The device owner was not confirmed.'));
    } on LocalAuthException catch (e, stack) {
      return ZenResult.err(
        ZenUnauthorizedError(
          'The device owner could not be confirmed: ${e.description ?? e.code.name}',
          stackTrace: stack,
        ),
      );
    } on PlatformException catch (e, stack) {
      return ZenResult.err(
        ZenUnknownError('The device owner check failed: ${e.message}', stackTrace: stack),
      );
    }
  }
}
