# Changelog

## 0.1.0

- Initial release. `ZenDeviceStoreKey`, moved out of `zen_store_cloudkit` (where it was
  `ZenKeychainStoreKey`) so every Local application has it on every platform. It refuses to make a
  key when the data directory already holds files (ADR-075).
