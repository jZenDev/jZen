import 'zen_locales.dart';

/// Where an application keeps the language its person chose, on the device.
///
/// A port, because `zen_core` is framework-free and the backing differs by platform. [read] is
/// synchronous on purpose: a locale is needed to build the first frame, so the implementation
/// loads its storage before `runApp` and answers from memory.
abstract interface class ZenLocaleStore {
  /// The stored language tag, or null when nothing has been stored.
  String? read();

  /// Stores [tag] so the next launch finds it.
  Future<void> write(String tag);
}

/// A [ZenLocaleStore] that lives only as long as the process - the default for tests, and the
/// honest answer for a run that has nowhere to write.
final class ZenMemoryLocaleStore implements ZenLocaleStore {
  ZenMemoryLocaleStore([this._tag]);

  String? _tag;

  @override
  String? read() => _tag;

  @override
  Future<void> write(String tag) async => _tag = tag;
}

/// The language an application starts in, and how a person's choice is remembered.
///
/// The order on launch is: the language the person chose, if it is still supported; else the
/// device's own language, if the application supports it; else [fallback]. The sign-in screen is
/// shown before any session exists, so none of this involves a server.
///
/// [supported] is the **application's** set (ADR-044), and it is checked on every path, so a
/// stored tag that is no longer supported (a language was removed in an update) falls through to
/// the next source instead of reaching `MaterialApp.locale`.
///
/// The server keeps its own copy of the language (`users.language`, which decides the language of
/// e-mail); this class does not touch it. Changing it is `IdentityRepository.setLanguage`.
final class ZenLocalePreference {
  ZenLocalePreference({
    required List<String> supported,
    required this.store,
    this.fallback = ZenLocales.fallback,
  }) : supported = List.unmodifiable(supported) {
    if (!this.supported.contains(fallback)) {
      throw ArgumentError.value(fallback, 'fallback', 'must be one of the supported languages');
    }
  }

  /// The languages the application supports.
  final List<String> supported;

  /// The persisted choice.
  final ZenLocaleStore store;

  /// The language used when neither the person nor the device names a supported one.
  final String fallback;

  /// The supported language [tag] names, matched on its primary subtag (`pl-PL` names `pl`), or
  /// null when it is absent, blank or not supported. Unlike [ZenLocales.resolve] this does not
  /// fall back, so a caller can tell a match from a substitution.
  String? match(String? tag) {
    if (tag == null || tag.trim().isEmpty) return null;
    final primary = tag.trim().toLowerCase().split(RegExp('[-_]')).first;
    return supported.contains(primary) ? primary : null;
  }

  /// The language to start in; [deviceTags] are the device's languages, most preferred first.
  String initial(Iterable<String> deviceTags) {
    final stored = match(store.read());
    if (stored != null) return stored;
    for (final tag in deviceTags) {
      final device = match(tag);
      if (device != null) return device;
    }
    return fallback;
  }

  /// Remembers [tag] and returns the language stored. Throws [ArgumentError] for a language the
  /// application does not support: a picker only offers supported ones, so reaching here with
  /// another is a bug, and substituting the fallback would hide it. A failed write surfaces as
  /// the error it is.
  Future<String> choose(String tag) async {
    final language = match(tag);
    if (language == null) {
      throw ArgumentError.value(tag, 'tag', 'is not a supported language');
    }
    await store.write(language);
    return language;
  }
}
