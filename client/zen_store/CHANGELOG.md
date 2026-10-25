# Changelog

## 0.1.0

- Initial release. `ZenStore` and typed `ZenCollection`s over proto messages, AES-256-GCM files
  on the device, merged per field by version vector; `ZenConflict` for what only a person may
  settle, with `conflicts`, `conflictFor` and `resolve`; `ZenSyncTransport` and `ZenSyncStatus`,
  `ZenFolderCloud` (a CloudKit stand-in for development), `ZenSyncReport` and `ZenStorageError`
  (ADR-065).
