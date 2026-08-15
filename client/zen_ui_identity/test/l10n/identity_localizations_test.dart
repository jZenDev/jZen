import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import '../support/localized_app.dart';

/// The typed replacement for the retired `IdentityMessages` suite (ROADMAP step 7b, ADR-009).
///
/// The old tests proved a string key reached a lookup table. There is no lookup table now - a
/// misspelled key does not compile - so these prove the two things a compiler cannot: that the
/// package ships the locales the framework declares with real wording behind each, and that
/// changing the ambient locale re-renders a live screen in the other language.
class _IdleRepository implements IdentityRepository {
  const _IdleRepository();

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async => const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<IdentityContract>> registerWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<void>> restorePassword({required String email}) async =>
      const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<IdentityContract>> exchangeLinkSession({
    required String accessToken,
    String? refreshToken,
  }) async => const ZenResult.err(ZenUnknownError('not implemented'));

  @override
  Future<ZenResult<void>> setPassword({required String password}) async =>
      const ZenResult.err(ZenUnknownError('not implemented'));

  @override
  // No fake here resumes a persisted session: sessionClientProvider defaults to null, so the
  // store returns before it would ever call this. Failing loudly beats a silent empty success.
  Future<ZenResult<IdentityContract>> refreshSession() async =>
      const ZenResult.err(ZenUnknownError('refreshSession not stubbed'));

  @override
  Future<ZenResult<void>> logout() async => const ZenResult.ok(null);
}

/// An application's own Polish for this package's strings, supplied without jZen shipping `pl`
/// (ADR-044). Subclassing the exported `abstract IdentityLocalizations` is the documented seam;
/// it is also why a new framework string cannot be missed - the override stops compiling.
class _PlIdentityLocalizations extends IdentityLocalizationsEn {
  _PlIdentityLocalizations() : super('pl');

  @override
  String get loginTitle => 'Zaloguj się';

  @override
  String get loginButton => 'Zaloguj się';
}

class _PlIdentityDelegate extends LocalizationsDelegate<IdentityLocalizations> {
  const _PlIdentityDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'pl';

  // SynchronousFuture, like every generated delegate: an async load leaves Localizations without
  // this type for a frame, and the framework's own delegate answers in its place.
  @override
  Future<IdentityLocalizations> load(Locale locale) =>
      SynchronousFuture<IdentityLocalizations>(_PlIdentityLocalizations());

  @override
  bool shouldReload(_PlIdentityDelegate old) => false;
}

void main() {
  test('ships exactly the locales ZenLocales declares', () {
    expect(IdentityLocalizations.supportedLocales.map((l) => l.languageCode), ZenLocales.shipped);
  });

  // ADR-044: an application may support a locale this package ships no strings for. The
  // generated delegate declines it, which leaves IdentityLocalizations.of(context) null and
  // crashes the first screen to read a string; the degrading delegate resolves to the fallback.
  test('the degrading delegate accepts an unshipped locale and loads the fallback', () async {
    expect(identityLocaleDelegate.isSupported(const Locale('pl')), isTrue);
    expect(IdentityLocalizations.delegate.isSupported(const Locale('pl')), isFalse);

    final pl = await identityLocaleDelegate.load(const Locale('pl'));
    final en = await identityMessages(ZenLocales.en);
    expect(pl.loginTitle, en.loginTitle);

    // Still exact where it can be: an unshipped tag degrades, a shipped one does not.
    final uk = await identityLocaleDelegate.load(const Locale('uk', 'UA'));
    expect(uk.loginTitle, 'Увійти');
  });

  testWidgets('a framework screen renders in English under an unshipped app locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(const _IdleRepository())],
        child: localizedApp(
          home: const LoginScreen(),
          locale: 'pl',
          supported: const [ZenLocales.en, ZenLocales.uk, 'pl'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Degraded, not crashed - which is the whole point.
    expect(find.widgetWithText(FilledButton, 'Log In'), findsOneWidget);
  });

  testWidgets('an app-supplied delegate composed first wins over the framework wording', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(const _IdleRepository())],
        child: localizedApp(
          home: const LoginScreen(),
          locale: 'pl',
          supported: const [ZenLocales.en, ZenLocales.uk, 'pl'],
          extraDelegates: const [_PlIdentityDelegate()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Zaloguj się'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log In'), findsNothing);
  });

  test('every locale carries its own wording', () async {
    final en = await identityMessages(ZenLocales.en);
    final uk = await identityMessages(ZenLocales.uk);

    expect(en.loginTitle, 'Log In');
    expect(uk.loginTitle, 'Увійти');
    expect(en.validationPasswordMismatch, 'Passwords do not match');
    expect(uk.validationPasswordMismatch, 'Паролі не збігаються');
  });

  test('errorText maps each modelled failure to its localized wording', () async {
    final uk = await identityMessages(ZenLocales.uk);

    expect(uk.errorText(const ZenUnauthorizedError('x')), uk.errorUnauthorized);
    expect(uk.errorText(const ZenNotFoundError('x')), uk.errorNotFound);
    expect(uk.errorText(const ZenValidationError('x')), uk.errorValidation);
    expect(uk.errorText(const ZenConflictError('x')), uk.errorConflict);
  });

  test('errorText prefers a server explanation over a generic one', () async {
    final en = await identityMessages(ZenLocales.en);

    // An error jZen does not model carries its own message, which beats unknownError.
    expect(en.errorText(const ZenUnknownError('relay refused')), 'relay refused');
  });

  testWidgets('switching the ambient locale re-renders the screen', (tester) async {
    Widget app(String locale) => ProviderScope(
      overrides: [identityRepositoryProvider.overrideWithValue(const _IdleRepository())],
      child: localizedApp(home: const LoginScreen(), locale: locale),
    );

    await tester.pumpWidget(app(ZenLocales.en));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Log In'), findsOneWidget);
    expect(find.text('Reset Password'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);

    // The same tree, one locale later: no reload, no bundle fetch, no key lookup.
    await tester.pumpWidget(app(ZenLocales.uk));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Увійти'), findsOneWidget);
    expect(find.text('Скинути пароль'), findsOneWidget);
    expect(find.text('Зареєструватися'), findsOneWidget);
    expect(find.text('Reset Password'), findsNothing);
    expect(find.text('Sign Up'), findsNothing);
  });
}
