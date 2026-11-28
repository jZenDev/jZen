# zen_save_file

**"Save this data to a file the person chooses", the same call on every platform.** An
application never names a platform plugin or branches on the platform:

```dart
final saved = await zenSaveFile('export.json', bytes, mimeType: 'application/json');
if (saved) {
  // written
} else {
  // the person cancelled: nothing was written, and that is not an error
}
```

- iOS and Android: the platform's own save or share-to-Files sheet.
- macOS, Windows, Linux: the save panel.
- Web: a download.
- A write the platform refuses throws a `ZenSaveFileError`, so a failure is never reported as a
  cancel or as saved.

The sheet is `file_picker`'s `saveFile`, which writes the bytes itself on every platform. On iOS
and macOS it is a Swift package (`file_picker_darwin` ships a `Package.swift`), so no runner needs a
`Podfile`; this package adds no native code of its own.

`ZenSaveFilePort` is the seam under the plugin, so the suite checks the capability's rules (a known
byte string is saved under its name and reads back, a cancel writes nothing, a refused write throws)
with a fake platform.

## Temporary copies on iOS

To show the save sheet, the plugin first writes the bytes to a file under the app's temporary
directory. This package requires `file_picker_darwin` 2.5.2 or newer, which deletes that file when
the request ends. On an iOS 27.0 simulator no copy remained after a save or after the sheet was
swiped away. An empty `tmp/flutter_file_picker` folder stays.

Some copies can still survive, in plain text, and this package has no call that removes them:

- Seen on an iOS 27.0 simulator: if the app is killed while the sheet is open, that export survives
  the relaunch and a later `zenSaveFile` call. The plugin deletes only the current request's file.
- Read from the plugin's source and changelog, not observed: upgrading does not remove copies that
  an older release left. 2.5.1 left them in `tmp/flutter_file_picker`. Releases before 2.5.1 wrote
  outside that folder, so the plugin's own `clearTemporaryFiles()` misses them; they stay until iOS
  clears the temporary directory.

## Verification

The suite runs on the host and stands in for the plugin. Checked by hand on 2026-11-28 with a
throwaway app: the sheet on the iOS simulator as above, and debug builds for the iOS simulator and
macOS.

**Not verified:** the sheet on a real iOS device, on Android or on macOS, and a release runner
build.
