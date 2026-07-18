import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_localization/zen_localization.dart';
import 'package:zen_ui_identity/src/l10n/identity_messages.dart';
import 'package:zen_ui_identity/src/screens/login_screen.dart';
import 'package:zen_ui_identity/src/state/identity_repository.dart';
import 'package:zen_ui_identity/src/theme/identity_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements IdentityRepository {
  final Future<ZenResult<IdentityContract>> Function(String, String)? _login;
  _FakeRepo({
    Future<ZenResult<IdentityContract>> Function(String, String)? login,
  }) : _login = login;

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async =>
      const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) async {
    if (_login != null) return _login(email, password);
    return const ZenResult.err(ZenUnknownError('not implemented'));
  }

  @override
  Future<ZenResult<IdentityContract>> registerWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('no'));

  @override
  Future<ZenResult<void>> restorePassword({required String email}) async =>
      const ZenResult.err(ZenUnknownError('no'));

  @override
  Future<ZenResult<void>> logout() async =>
      const ZenResult.err(ZenUnknownError('no'));
}

class _FakeLocalization implements ZenLocalizationService {
  final Map<String, String> _map;
  _FakeLocalization(this._map);
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
  final msgs = IdentityMessages(
    _FakeLocalization({
      'login.title': 'Login',
      'email.label': 'Email',
      'password.label': 'Password',
      'login.button': 'Sign In',
      'validation.required': 'Required',
      'restore.password.title': 'Reset Password',
      'register.title': 'Register',
    }),
    en,
  );

  testWidgets('shows validation errors when fields empty', (tester) async {
    final repo = _FakeRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: ThemeData(extensions: [IdentityThemeExtension.fallback()]),
          home: LoginScreen(messages: msgs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsNWidgets(2));
  });

  testWidgets('forgot password and register callbacks are invoked', (
    tester,
  ) async {
    final repo = _FakeRepo();
    var forgot = false;
    var register = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: ThemeData(extensions: [IdentityThemeExtension.fallback()]),
          home: LoginScreen(
            messages: msgs,
            onForgotPasswordClick: () => forgot = true,
            onRegisterClick: () => register = true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(forgot, isTrue);
    expect(register, isTrue);
  });

  testWidgets('successful login calls onLoginSuccess', (tester) async {
    final contract = IdentityContract(
      id: 'u1',
      lifecycle: const IdentityLifecycleContract(state: 'active'),
      authority: const AuthorityContract(roles: [], capabilities: []),
      createdAt: ZenTimestamp.now().millisecondsSinceEpoch,
    );

    final repo = _FakeRepo(login: (_, _) async => ZenResult.ok(contract));

    var called = false;
    Identity? loginIdentity;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: ThemeData(extensions: [IdentityThemeExtension.fallback()]),
          home: LoginScreen(
            messages: msgs,
            onLoginSuccess: () => called = true,
            onLoginSuccessWithIdentity: (id) => loginIdentity = id,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));

    await tester.enterText(fields.at(0), 'a@b.com');
    await tester.enterText(fields.at(1), 'password');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(loginIdentity?.id.value, 'u1');
  });

  testWidgets('failed login shows error SnackBar', (tester) async {
    final repo = _FakeRepo(
      login: (_, _) async =>
          const ZenResult.err(ZenUnknownError('bad credentials')),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: ThemeData(extensions: [IdentityThemeExtension.fallback()]),
          home: LoginScreen(messages: msgs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'a@b.com');
    await tester.enterText(fields.at(1), 'password');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('bad credentials'), findsOneWidget);
  });
}
