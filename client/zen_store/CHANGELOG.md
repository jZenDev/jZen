# Changelog

## Unreleased

- `ZenStore.writeAll(ZenBatch)`: puts and deletes across collections and shards saved as one — a crash leaves all of the batch or none (a `journal.zen` finished at the next `open`); to a transport it is ordinary per-record changes (ADR-084, #232).
- `ZenPairing`: the 77-character code (QR text behind `zenpair1:`) that carries the sync key to a new device (ADR-077).

## 0.1.0

- Initial release. `ZenStore` and typed `ZenCollection`s over proto messages, AES-256-GCM files
  on the device, merged per field by version vector; `ZenConflict` for what only a person may
  settle, with `conflicts`, `conflictFor` and `resolve`; `ZenSyncTransport` and `ZenSyncStatus`,
  `ZenFolderCloud` (a CloudKit stand-in for development), `ZenSyncReport` and `ZenStorageError`
  (ADR-065).
