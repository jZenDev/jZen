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
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async =>
      const ZenResult.ok(null);

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
  Future<ZenResult<void>> logout() async => const ZenResult.ok(null);
}

void main() {
  test('ships exactly the locales ZenLocales declares', () {
    expect(
      IdentityLocalizations.supportedLocales.map((l) => l.languageCode),
      ZenLocales.supported,
    );
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

  testWidgets('switching the ambient locale re-renders the screen', (
    tester,
  ) async {
    Widget app(String locale) => ProviderScope(
      overrides: [
        identityRepositoryProvider.overrideWithValue(const _IdleRepository()),
      ],
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
