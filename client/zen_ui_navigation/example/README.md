# zen_ui_navigation example

A small Flutter app demonstrating `zen_ui_navigation`'s adaptive `ZenNavigation` across
platforms. jZen client config is compile-time, so pass the target platform with
`--dart-define=ZEN_PLATFORM=...`:

```bash
flutter run -d chrome  --dart-define=ZEN_PLATFORM=web
flutter run -d macos   --dart-define=ZEN_PLATFORM=macos
flutter run -d windows --dart-define=ZEN_PLATFORM=windows
flutter run -d linux   --dart-define=ZEN_PLATFORM=linux
flutter run -d ios     --dart-define=ZEN_PLATFORM=ios
flutter run -d android --dart-define=ZEN_PLATFORM=android
```
