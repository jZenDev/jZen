import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zen_core/zen_core.dart';

/// Confirms that the person holding the device is its owner, for resetting a forgotten PIN.
abstract interface class ZenOwnerCheck {
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
