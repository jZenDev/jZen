# Changelog

## 0.1.0

- Initial release. `ZenSharedFolderSync`: a `ZenSyncTransport` over a synced folder, one
  subfolder per device, every file AES-256-GCM encrypted with a key derived from the shared sync
  key and its path bound in as associated data. `ZenFolderAccess` with `ZenDirectoryAccess` for
  `dart:io` (ADR-075).
