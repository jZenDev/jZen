# Changelog

## Unreleased

- Depends on `local_auth_android`, `local_auth_darwin` and `local_auth_platform_interface` instead of `local_auth`, so no consumer resolves `local_auth_windows`; Windows answers "no owner check" from Dart, so "Forgot PIN?" erases this device's copy there as on Linux (ADR-081, ADR-086). `ZenDeviceOwnerCheck` takes a `LocalAuthPlatform`, not a `LocalAuthentication`.
- "Forgot PIN?" on a device with no owner check (Linux): erase this device's copy, via
  `ZenPinLock.load(eraseDeviceCopy:)` (ADR-078). `ZenOwnerCheck` gains `isAvailable()`.
- Desktop windows relock after being unfocused for `relockAfter`.

## 0.1.0

- Initial release. `ZenPinLock` (hashed PIN in the Keychain, wrong-attempt shut-out, recovery
  through the device owner check), `ZenLockGate`, the unlock / set-up / turn-off screens and
  `ZenPinLockSwitch`, in English and Ukrainian (ADR-065).
