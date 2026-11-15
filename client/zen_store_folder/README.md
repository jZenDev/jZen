# zen_store_folder

**Choosing the folder a jZen Local application syncs through, and reaching it.**
`zen_store_shared_folder` is pure Dart and takes a `ZenFolderAccess`; this package supplies one on
every platform that uses it (ADR-076):

- Windows, Linux: the operating system's folder dialog (`file_picker`), reached with `dart:io`.
- Android: the Storage Access Framework (`saf_util`, `saf_stream`) through `ZenSafFolderAccess`,
  with the persistable read-write grant taken when the person picks.

```dart
final choice = await ZenFolderPicker.pick();                   // null if cancelled
keep(choice.reference);                                        // a path or a content:// tree
final later = ZenFolderPicker.restore(kept);                   // on the next launch
ZenSync.start(store, sharedFolder: later.access, syncKey: key);
```

`ZenSafPort` is the seam under the two plugins, so the suite checks the adapter's rules (write by
temporary document, no rename over an existing one, a withdrawn grant) with a fake tree.

**Not verified:** the two plugins against a real provider and sync app on an Android device,
and whether the grant survives a restart (spike 0.1 of the jZen Local plan).
