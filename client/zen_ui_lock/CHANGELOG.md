# Changelog

## Unreleased

- "Forgot PIN?" on a device with no owner check (Linux): erase this device's copy, via
  `ZenPinLock.load(eraseDeviceCopy:)` (ADR-075). `ZenOwnerCheck` gains `isAvailable()`.
- Desktop windows relock after being unfocused for `relockAfter`.

## 0.1.0

- Initial release. `ZenPinLock` (hashed PIN in the Keychain, wrong-attempt shut-out, recovery
  through the device owner check), `ZenLockGate`, the unlock / set-up / turn-off screens and
  `ZenPinLockSwitch`, in English and Ukrainian (ADR-065).
