import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import 'providers.dart';

/// Where the language a person chose could not be saved. The screens are in the chosen language
/// either way.
enum LanguageSaveFailure {
  /// The device could not store it, so it will not outlive a restart.
  device,

  /// The server was not told, or refused, so e-mail may keep arriving in the previous language.
  account,
}

/// What happens when a person picks a language: the device first, then their account.
///
/// The device applies the choice and stores it without waiting on the server, and nothing the
/// server answers undoes it: the picker must work offline and before any sign-in. The server is
/// then told, because `users.language` - not anything on the device - decides the language of the
/// e-mail it sends.
///
/// The server is told only of a choice the device has stored. After a failed device write the
/// next launch returns to the old language, so an account already moved to the new one would
/// disagree with it.
///
/// The state is the failure worth telling the person about, or null when there is none. It is
/// held here rather than by the picker because the answer can arrive after the picker has left
/// the screen. Every failure is logged, including those not worth showing: one a newer choice
/// will report for itself, and one about an account that is no longer the signed-in one.
class LanguageChoice extends Notifier<LanguageSaveFailure?> {
  /// How long the server has to answer. Without a limit a request that is never answered would
  /// report nothing and hold up every later choice.
  static const Duration accountTimeout = Duration(seconds: 30);

  /// Completes when every earlier choice has finished with the server.
  Future<void> _earlier = Future.value();

  /// The latest choice made, and the latest one the device stored - the only kind the server
  /// hears of.
  int _latest = 0;
  int _latestStored = 0;

  @override
  LanguageSaveFailure? build() => null;

  Future<void> choose(Locale locale) async {
    final choice = ++_latest;
    // Whose choice this is, read before anything is awaited.
    final chooser = _signedInId();
    final earlier = _earlier;
    final done = Completer<void>();
    _earlier = done.future;
    try {
      if (!await _saveOnDevice(choice, locale)) return;
      // Writes may finish out of the order they were made in.
      _latestStored = math.max(_latestStored, choice);
      // No session, no account to tell.
      if (chooser == null) return;
      // One request at a time: two side by side may be applied in either order, leaving the
      // account in the language the person moved away from.
      await earlier;
      if (!ref.mounted) {
        ZenLogger.instance.warn('The chosen language was not sent: the app is closing');
        return;
      }
      // A newer choice replaced this one while it waited; sending it would only delay that one.
      if (choice != _latestStored) return;
      // The call changes whoever is signed in when it is sent, which after a wait may no longer
      // be the person who chose.
      if (_signedInId() != chooser) {
        ZenLogger.instance.warn('The chosen language was not sent: its session has ended');
        return;
      }
      await _saveOnAccount(choice, chooser, locale.languageCode);
    } finally {
      done.complete(earlier);
    }
  }

  /// Who is signed in, or null when nobody is. A session still loading counts as nobody: during a
  /// sign-out it goes on naming the person who is leaving.
  IdentityId? _signedInId() {
    final session = ref.read(identitySessionStoreProvider);
    return session.isLoading ? null : session.value?.id;
  }

  Future<bool> _saveOnDevice(int choice, Locale locale) async {
    try {
      await ref.read(localeProvider.notifier).setLocale(locale);
      return true;
    } on ArgumentError {
      // A language the app does not support is a bug in the caller, not a failed write.
      rethrow;
    } catch (error, stackTrace) {
      _fail(LanguageSaveFailure.device, () => choice == _latest, error, stackTrace);
      return false;
    }
  }

  Future<void> _saveOnAccount(int choice, IdentityId chooser, String language) async {
    // "Your account" and "choose again" are only true of the person who chose.
    bool worthShowing() => choice == _latestStored && _signedInId() == chooser;
    try {
      final result = await ref
          .read(identityRepositoryProvider)
          .setLanguage(language)
          .timeout(accountTimeout);
      result.fold((_) {}, (failure) => _fail(LanguageSaveFailure.account, worthShowing, failure));
    } catch (error, stackTrace) {
      // No answer in time, or a repository that threw instead of answering with a ZenResult:
      // either is a failed save.
      _fail(LanguageSaveFailure.account, worthShowing, error, stackTrace);
    }
  }

  /// Logs [error], and publishes [failure] if [worthShowing]; that is asked only while the app
  /// is still there to answer it.
  void _fail(
    LanguageSaveFailure failure,
    bool Function() worthShowing,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    ZenLogger.instance.error(
      'The chosen language was not saved (${failure.name})',
      error: error,
      stackTrace: stackTrace,
    );
    if (!ref.mounted || !worthShowing()) return;
    // Cleared first so that the same failure twice in a row is still a change a listener hears.
    state = null;
    state = failure;
  }
}

final languageChoiceProvider = NotifierProvider<LanguageChoice, LanguageSaveFailure?>(
  LanguageChoice.new,
);
