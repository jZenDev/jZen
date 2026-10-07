import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/src/screens/login_screen.dart';
import 'package:zen_ui_identity/src/state/identity_repository.dart';
import 'package:zen_ui_identity/src/widgets/identity_button.dart';
import 'package:zen_ui_identity/src/widgets/identity_text_field.dart';
import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show ZenButton;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/a11y.dart';
import '../support/localized_app.dart';

class _FakeRepo implements IdentityRepository {
  final Future<ZenResult<IdentityContract>> Function(String, String)? _login;
  _FakeRepo({Future<ZenResult<IdentityContract>> Function(String, String)? login}) : _login = login;

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async => const ZenResult.ok(null);

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
  Future<ZenResult<IdentityContract>> exchangeLinkSession({
    required String accessToken,
    String? refreshToken,
  }) async => const ZenResult.err(ZenUnknownError('not implemented'));

  @override
  Future<ZenResult<void>> setPassword({required String password, String? currentPassword}) async =>
      const ZenResult.err(ZenUnknownError('not implemented'));

  @override
  // No fake here resumes a persisted session: sessionClientProvider defaults to null, so the
  // store returns before it would ever call this. Failing loudly beats a silent empty success.
  Future<ZenResult<IdentityContract>> refreshSession() async =>
      const ZenResult.err(ZenUnknownError('refreshSession not stubbed'));

  @override
  Future<ZenResult<void>> logout() async => const ZenResult.err(ZenUnknownError('no'));
}

void main() {
  testWidgets('shows validation errors when fields empty', (tester) async {
    final repo = _FakeRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(home: LoginScreen()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ZenButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsNWidgets(2));
  });

  testWidgets('rejects an email that only contains an @ sign', (tester) async {
    final repo = _FakeRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(home: LoginScreen()),
      ),
    );

    await tester.pumpAndSettle();
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'a@');
    await tester.enterText(fields.at(1), 'password');
    await tester.tap(find.widgetWithText(ZenButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email'), findsOneWidget);
  });

  testWidgets('forgot password and register callbacks are invoked', (tester) async {
    final repo = _FakeRepo();
    var forgot = false;
    var register = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(
          home: LoginScreen(
            onForgotPasswordClick: () => forgot = true,
            onRegisterClick: () => register = true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign Up'));
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
        child: localizedApp(
          home: LoginScreen(
            onLoginSuccess: () => called = true,
            onLoginSuccessWithIdentity: (id) => loginIdentity = id,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final fields = find.byType(EditableText);
    expect(fields, findsNWidgets(2));

    await tester.enterText(fields.at(0), 'a@b.com');
    await tester.enterText(fields.at(1), 'password');
    await tester.tap(find.widgetWithText(ZenButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(loginIdentity?.id.value, 'u1');
  });

  testWidgets('failed login shows error SnackBar', (tester) async {
    final repo = _FakeRepo(
      login: (_, _) async => const ZenResult.err(ZenUnknownError('bad credentials')),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(home: LoginScreen()),
      ),
    );

    await tester.pumpAndSettle();
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'a@b.com');
    await tester.enterText(fields.at(1), 'password');
    await tester.tap(find.widgetWithText(ZenButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(find.text('bad credentials'), findsOneWidget);
  });

  // WCAG 2.1.1 Keyboard and 2.4.3 Focus Order: a keyboard-only user reaches every control in the
  // order they are read, and submits from the password field without reaching for the mouse.
  testWidgets('keyboard: Tab visits every control in reading order; Enter submits', (tester) async {
    final messages = await identityMessages('en');
    var attempts = 0;
    final repo = _FakeRepo(
      login: (_, _) async {
        attempts++;
        return const ZenResult.err(ZenUnknownError('bad credentials'));
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(
          home: LoginScreen(onForgotPasswordClick: () {}, onRegisterClick: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    String? focused() {
      final context = FocusManager.instance.primaryFocus?.context;
      return context?.findAncestorWidgetOfExactType<IdentityTextField>()?.label ??
          context?.findAncestorWidgetOfExactType<IdentityButton>()?.text;
    }

    final visited = <String?>[];
    for (int i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      visited.add(focused());
    }
    expect(visited, [
      messages.emailLabel,
      messages.passwordLabel,
      messages.restorePasswordTitle,
      messages.loginButton,
      messages.registerTitle,
    ]);

    // Back to the email field, type, move on with the keyboard's own "next", submit with "done".
    for (int i = 0; i < 4; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
    }
    expect(focused(), messages.emailLabel);
    tester.testTextInput.enterText('a@b.com');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(focused(), messages.passwordLabel);
    tester.testTextInput.enterText('password');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(attempts, 1);
  });

  for (final entry in auditThemes.entries) {
    testWidgets('meets AA text contrast and labels every target (${entry.key})', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = _FakeRepo(
        login: (_, _) async => const ZenResult.err(ZenUnknownError('bad credentials')),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [identityRepositoryProvider.overrideWithValue(repo)],
          child: localizedApp(
            theme: entry.value,
            home: LoginScreen(onForgotPasswordClick: () {}, onRegisterClick: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      // The failure SnackBar is painted in the theme's error colour; its text must still read.
      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'a@b.com');
      await tester.enterText(fields.at(1), 'password');
      await tester.tap(find.widgetWithText(ZenButton, 'Log In'));
      await tester.pumpAndSettle();
      expect(find.text('bad credentials'), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }
}
