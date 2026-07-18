# Changelog

## 0.1.0

- Initial port from `dartzen_core`: `ZenResult`/`ZenError`, `ZenLogger` (with
  platform-selected strategy), value objects (`ZenTimestamp`, `ZenLocale`, `EmailAddress`,
  `UserId`), guards (`ZenGuard`, `ZenTry`), `BaseResponse`, and the compile-time env/platform
  constants. Renamed `dz*` → `zen*` and `DZ_*` → `ZEN_*`; stripped the GCP/Firestore
  emulator constants.
