import 'package:flutter/services.dart';

/// Keeps what the app shows out of screenshots, screen recording, casting and the recents
/// thumbnail, by setting Android's `FLAG_SECURE` on the app's window.
///
/// Flutter never sets it, and the lock's cover only hides the app once it is painted, which the
/// recents snapshot may precede. The flag is the one thing the operating system honours for all
/// of them. It exists on Android only: iOS and the desktops give an app no equivalent, so there
/// [setSecure] answers false and changes nothing. [ZenLockGate] calls it for an application that
/// asks (`secureScreen`); an application with its own window to protect may call it directly.
abstract final class ZenScreenSecurity {
  static const MethodChannel _channel = MethodChannel('zen_ui_lock/screen');

  /// Sets or clears the flag. Returns whether the platform has one: false everywhere but Android,
  /// where it is not an error, only not applicable. A failure on Android is thrown, never hidden:
  /// a screen the app believes is protected and is not is the defect this exists to prevent.
  static Future<bool> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
      return true;
    } on MissingPluginException {
      return false;
    }
  }
}
