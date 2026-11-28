# Changelog

## 0.1.0

- `zenSaveFile`: save bytes to a file the person chooses on iOS, Android, desktop and web.
- Requires `file_picker_darwin` 2.5.2 or newer, so a save on iOS no longer leaves a copy of the
  bytes in the app's temporary directory once the request ends. A copy can still survive if the app
  is killed while the sheet is open, and upgrading does not remove copies that older releases left
  (see the README, "Temporary copies on iOS").
