# Changelog

## Unreleased

- The conflict screens show every version, including several from one device: cards under one name are numbered, the list names a device once with its number of versions, and settling many records at once leaves a record with several versions from one device to the person (ADR-089, #286).
- A choice on `ZenConflictResolveScreen` is no longer saved over a version it never showed: if a sync changed or settled the record since the screen was drawn, nothing is written, and the screen says so and redraws (#286).
- `ZenIssueAction.choose` (a choice among candidates) and `ZenIssueAction.text` (a short text): `ZenIssueScreen` asks for the input itself and calls `run` only when the person confirms; cancelling runs nothing.
- **Breaking:** `ZenIssueAction` is now sealed, with `ZenPlainIssueAction`, `ZenChoiceIssueAction` and `ZenTextIssueAction`. The `ZenIssueAction(label:, run:)` constructor is unchanged, but `run` now lives on the subtypes, so code that read `.run` from a `ZenIssueAction` must switch over the kinds.
- `ZenAddDeviceScreen`, `ZenJoinScreen`, `ZenQrScannerBuilder` and `ZenPairingCodeView`: pairing a new device with a code (ADR-077).

## 0.1.0

- Initial release. `ZenConflictBanner`, `ZenConflictsScreen`, `ZenConflictResolveScreen` and
  `ZenConflictSideCard` over `ZenConflictSource`, and `ZenSyncStatusBanner`, in English and Ukrainian (ADR-065).
