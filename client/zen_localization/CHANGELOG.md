# Changelog

## 0.1.0

- Initial port from `dartzen_localization`: `ZenLocalizationService`, config, cache,
  exceptions, and the platform-selected loader (`loader_flutter`/`loader_io`/`loader_stub`).
  Made Dart-pure (TA-3): `flutter`/`flutter_test` are dev-only dependencies so Dart-only
  consumers do not pull in the Flutter SDK. Renamed the dev-file prefix `dartzen.` → `zen.`.
