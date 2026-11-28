# Changelog

## Unreleased

- **Behaviour change:** `ZenConflict.sides` holds every version in dispute, so one device can have several sides (`ZenConflictSide.device` repeats). A second value attributed to the same device, a record written again after a delete, and an edit that only cleared a field against a delete were hidden; all devices holding the same state now answer the same sides. Do not index sides by device (ADR-089, #286).
- A top-level proto3 field with implicit presence set to its default is stored as unset, so `description = ''` and `clearDescription()` are one value and no longer conflict; `ZenStore.collection(explicitPresence: {…})` names the `optional` fields, which keep the distinction (#245).
- `expect` on `ZenCollection.put`/`delete` and `ZenBatch.put`/`delete`: a precondition run inside the write's turn against the record as it stands then, so a sync's delete cannot be written over (#251).
- `ZenStore.collection(syncs: false)`: a device-only collection, never sent or accepted by a transport, yet written atomically with synced collections by `writeAll` (#252).
- `ZenStore.writeAll(ZenBatch)`: puts and deletes across collections and shards saved as one — a crash leaves all of the batch or none (a `journal.zen` finished at the next `open`); to a transport it is ordinary per-record changes (ADR-084, #232).
- `ZenPairing`: the 77-character code (QR text behind `zenpair1:`) that carries the sync key to a new device (ADR-077).

## 0.1.0

- Initial release. `ZenStore` and typed `ZenCollection`s over proto messages, AES-256-GCM files
  on the device, merged per field by version vector; `ZenConflict` for what only a person may
  settle, with `conflicts`, `conflictFor` and `resolve`; `ZenSyncTransport` and `ZenSyncStatus`,
  `ZenFolderCloud` (a CloudKit stand-in for development), `ZenSyncReport` and `ZenStorageError`
  (ADR-065).
