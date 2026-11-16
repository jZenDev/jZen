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

**Not verified:** the sheet on a real iOS or Android device, and an iOS or macOS runner build —
the suite runs on the host and stands in for the plugin.
