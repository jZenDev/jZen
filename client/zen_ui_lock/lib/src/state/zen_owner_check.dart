import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:zen_core/zen_core.dart';

/// Confirms that the person holding the device is its owner, for resetting a forgotten PIN.
abstract interface class ZenOwnerCheck {
  /// Whether this device can check its owner at all: false (a success) on Linux and Windows, where
  /// jZen ships no implementation (ADR-086), and on a device with no passcode set up.
  /// "Forgot PIN?" then offers erasing this device's copy instead (ADR-078) — never a bare reset,
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
  final LocalAuthPlatform? _platform;

  /// Uses [platform], or the registered `local_auth` implementation (read at each call, so a
  /// platform registered after construction is honoured).
  ZenDeviceOwnerCheck({this._platform});

  LocalAuthPlatform get _auth => _platform ?? LocalAuthPlatform.instance;

  @override
  Future<ZenResult<bool>> isAvailable() async {
    // jZen depends on `local_auth`'s Android and Darwin implementations only. Its Windows plugin
    // cannot be compiled by Visual Studio 18 (ADR-081, ADR-086), and Linux never had one; asking
    // would reach the method-channel default and throw MissingPluginException.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      return const ZenResult.ok(false);
    }
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
      final passed = await _auth.authenticate(
        localizedReason: reason,
        authMessages: const <AuthMessages>[],
        // The legacy dialogs are off, exactly as `LocalAuthentication.authenticate` sends it.
        options: const AuthenticationOptions(useErrorDialogs: false),
      );
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
