# Changelog

## Unreleased

- `ZenIssueAction.choose` (a choice among candidates) and `ZenIssueAction.text` (a short text): `ZenIssueScreen` asks for the input itself and calls `run` only when the person confirms; cancelling runs nothing.
- **Breaking:** `ZenIssueAction` is now sealed, with `ZenPlainIssueAction`, `ZenChoiceIssueAction` and `ZenTextIssueAction`. The `ZenIssueAction(label:, run:)` constructor is unchanged, but `run` now lives on the subtypes, so code that read `.run` from a `ZenIssueAction` must switch over the kinds.
- A `ZenIssueAction.choose` with one candidate no longer asserts when tapped: the candidate is shown, and the person picks it and continues like any other choice.
- `ZenAddDeviceScreen`, `ZenJoinScreen`, `ZenQrScannerBuilder` and `ZenPairingCodeView`: pairing a new device with a code (ADR-077).

## 0.1.0

- Initial release. `ZenConflictBanner`, `ZenConflictsScreen`, `ZenConflictResolveScreen` and
  `ZenConflictSideCard` over `ZenConflictSource`, and `ZenSyncStatusBanner`, in English and Ukrainian (ADR-065).
