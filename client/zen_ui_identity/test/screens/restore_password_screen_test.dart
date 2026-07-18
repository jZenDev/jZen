import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_localization/zen_localization.dart';
import 'package:zen_ui_identity/src/l10n/identity_messages.dart';
import 'package:zen_ui_identity/src/screens/restore_password_screen.dart';
import 'package:zen_ui_identity/src/state/identity_repository.dart';
import 'package:zen_ui_identity/src/theme/identity_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements IdentityRepository {
  ZenResult<void> restoreResult;
  _FakeRepo({ZenResult<void>? restoreResult})
    : restoreResult =
          restoreResult ?? const ZenResult.err(ZenUnknownError('not set'));

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async =>
      const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('not implemented'));

  @override
  Future<ZenResult<IdentityContract>> registerWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('not implemented'));

  @override
  Future<ZenResult<void>> restorePassword({required String email}) async =>
      restoreResult;

  @override
  Future<ZenResult<void>> logout() async =>
      const ZenResult.err(ZenUnknownError('not implemented'));
}

class _FakeLocalization implements ZenLocalizationService {
  final Map<String, String> _map;
  _FakeLocalization(this._map);

  Map<String, String> getGlobal(String language) => _map;

  Map<String, String> getModule(String module, String language) => _map;

  @override
  String translate(
    String key, {
    required String language,
    String? module,
    Map<String, dynamic> params = const {},
  }) => _map[key] ?? key;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const en = 'en';

  final messages = IdentityMessages(
    _FakeLocalization({
      'restore.password.title': 'Restore',
      'restore.password.info': 'Enter email to restore',
      'email.label': 'Email',
      'send.reset.link.button': 'Send',
      'reset.link.sent.success': 'Sent',
      'validation.required': 'Required',
      'validation.email': 'Bad email',
      'error.not_found': 'Not found',
    }),
    en,
  );

  testWidgets('success shows success snackbar and calls callback', (
    tester,
  ) async {
    final repo = _FakeRepo(restoreResult: const ZenResult.ok(null));
    var called = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: ThemeData(extensions: [IdentityThemeExtension.fallback()]),
          home: RestorePasswordScreen(
            messages: messages,
            onRestoreSuccess: () => called = true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // enter a valid email
    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Sent'), findsOneWidget);
    expect(called, isTrue);
  });

  testWidgets('error shows error snackbar with error color', (tester) async {
    final repo = _FakeRepo(
      restoreResult: const ZenResult.err(ZenNotFoundError('no')),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: ThemeData(extensions: [IdentityThemeExtension.fallback()]),
          home: RestorePasswordScreen(messages: messages),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Not found'), findsOneWidget);

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.backgroundColor, IdentityThemeExtension.fallback().errorColor);
  });
}
