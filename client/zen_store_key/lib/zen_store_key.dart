/// jZen Store Key - the key a jZen Local application's `zen_store` encrypts its files with, on
/// iOS, macOS, Android, Windows and Linux.
///
/// - [ZenDeviceStoreKey]: made once, kept in the platform's secret storage, never beside the data
///
/// See docs/architecture/DECISIONS.md ADR-075.
library;

export 'src/zen_device_store_key.dart';
