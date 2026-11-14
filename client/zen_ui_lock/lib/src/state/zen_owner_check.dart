import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zen_core/zen_core.dart';

/// Confirms that the person holding the device is its owner, for resetting a forgotten PIN.
abstract interface class ZenOwnerCheck {
  /// Whether this device can check its owner at all: false (a success) on Linux, where
  /// `local_auth` has no implementation, and on a device with no passcode or Windows Hello set up.
  /// "Forgot PIN?" then offers erasing this device's copy instead (ADR-075) — never a bare reset,
  /// which would hand the data to whoever holds the device.
  ///
  /// A failure to find out is an error, not "false": a glitch on a phone that does have an owner
  /// check must not push the person toward erasing their data.
  Future<ZenResult<bool>> isAvailable();

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
  Future<ZenResult<bool>> isAvailable() async {
    // `local_auth` registers nothing on Linux; asking would throw MissingPluginException.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) return const ZenResult.ok(false);
    try {
      return ZenResult.ok(await _auth.isDeviceSupported());
    } on MissingPluginException {
      // The documented "this platform has no owner check" case, and the only exception that means it.
      return const ZenResult.ok(false);
    } on Object catch (e, stack) {
      return ZenResult.err(
        ZenUnknownError('Whether the device can check its owner is unknown: $e', stackTrace: stack),
      );
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
