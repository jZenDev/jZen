import 'dart:async';

import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_localization/zen_localization.dart';
import 'package:zen_ui_identity/src/l10n/identity_messages.dart';
import 'package:zen_ui_identity/src/screens/register_screen.dart';
import 'package:zen_ui_identity/src/state/identity_session_store.dart';
import 'package:zen_ui_identity/src/theme/identity_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Helper to create a valid Identity instance for tests
Identity makeTestIdentity() {
  final idResult = IdentityId.create('1');
  return idResult.fold(
    (id) => Identity.createPending(id: id),
    (err) => throw Exception('Invalid IdentityId'),
  );
}

// Test double for IdentitySessionStore
class TestIdentitySessionStore extends IdentitySessionStore {
  @override
  FutureOr<Identity?> build() async {
    // For tests, always start with a non-loading, unauthenticated state
    return null;
  }

  Future<ZenResult<Identity>> Function(String, String)? onRegister;
  @override
  Future<ZenResult<Identity>> register(String email, String password) {
    if (onRegister != null) {
      return onRegister!(email, password);
    }
    throw UnimplementedError();
  }
}

void main() {
  late TestIdentitySessionStore testStore;
  late IdentityMessages messages;

  setUp(() {
    testStore = TestIdentitySessionStore();
    const config = ZenLocalizationConfig(isProduction: false);
    final service = ZenLocalizationService(config: config);
    // Inject identity.en.json keys directly into the module cache for tests
    service.cache.setModule('identity', 'en', {
      'login.title': 'Log In',
      'register.title': 'Sign Up',
      'restore.password.title': 'Reset Password',
      'email.label': 'Email',
      'password.label': 'Password',
      'confirm.password.label': 'Confirm Password',
      'login.button': 'Log In',
      'register.button': 'Create Account',
      'send.reset.link.button': 'Send Link',
      'profile.title': 'Profile',
      'logout.button': 'Log Out',
      'roles.title': 'Your Roles',
      'unknown.error': 'An unknown error occurred.',
      'validation.required': 'Required',
      'validation.email': 'Invalid email',
      'validation.password.mismatch': 'Passwords do not match',
      'error.unauthorized': 'Invalid credentials or unauthorized access.',
      'error.not_found': 'Requested resource not found.',
      'error.validation': 'Validation failed. Please check your input.',
      'error.conflict': 'A conflict occurred (e.g., user already exists).',
      'restore.password.info':
          "Enter your email address and we'll send you a link to reset your password.",
      'reset.link.sent.success': 'Reset link sent to your email',
      'already.have.account': 'Already have an account?',
      'not.authenticated': 'Not authenticated',
      'roles.label': 'Roles:',
    });
    messages = IdentityMessages(service, 'en');
  });

  Widget buildTestable({
    VoidCallback? onRegisterSuccess,
    VoidCallback? onLoginClick,
  }) {
    return ProviderScope(
      overrides: [identitySessionStoreProvider.overrideWith(() => testStore)],
      child: MaterialApp(
        theme: ThemeData(extensions: [IdentityThemeExtension.fallback()]),
        home: RegisterScreen(
          messages: messages,
          onRegisterSuccess: onRegisterSuccess,
          onLoginClick: onLoginClick,
        ),
      ),
    );
  }

  testWidgets('renders all fields and buttons', (tester) async {
    await tester.pumpWidget(buildTestable());
    await tester.pumpAndSettle();
    expect(find.text(messages.registerTitle), findsOneWidget);
    expect(find.text(messages.emailLabel), findsOneWidget);
    expect(find.text(messages.passwordLabel), findsOneWidget);
    expect(find.text(messages.confirmPasswordLabel), findsOneWidget);
    expect(find.text(messages.registerButton), findsOneWidget);
    expect(find.text(messages.loginButton), findsOneWidget);
  });

  testWidgets('shows validation errors for empty fields', (tester) async {
    await tester.pumpWidget(buildTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text(messages.registerButton));
    await tester.pumpAndSettle();
    expect(find.text(messages.validationRequired), findsNWidgets(2));
  });

  testWidgets('shows validation error for invalid email', (tester) async {
    await tester.pumpWidget(buildTestable());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'invalid');
    await tester.tap(find.text(messages.registerButton));
    await tester.pumpAndSettle();
    expect(find.text(messages.validationEmail), findsOneWidget);
  });

  testWidgets('shows validation error for password mismatch', (tester) async {
    await tester.pumpWidget(buildTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.enterText(find.byType(TextFormField).at(2), 'password2');
    await tester.tap(find.text(messages.registerButton));
    await tester.pumpAndSettle();
    expect(find.text(messages.validationPasswordMismatch), findsOneWidget);
  });

  testWidgets('calls onRegisterSuccess on successful registration', (
    tester,
  ) async {
    bool called = false;
    testStore.onRegister = (email, password) async {
      return ZenResult.ok(makeTestIdentity());
    };
    await tester.pumpWidget(
      buildTestable(
        onRegisterSuccess: () {
          called = true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.enterText(find.byType(TextFormField).at(2), 'password');
    await tester.tap(find.text(messages.registerButton));
    await tester.pumpAndSettle();
    expect(called, isTrue);
  });

  testWidgets('shows error SnackBar on registration failure', (tester) async {
    testStore.onRegister = (email, password) async {
      return const ZenResult.err(ZenValidationError('fail'));
    };
    await tester.pumpWidget(buildTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.enterText(find.byType(TextFormField).at(2), 'password');
    await tester.tap(find.text(messages.registerButton));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('login button calls onLoginClick', (tester) async {
    bool called = false;
    await tester.pumpWidget(
      buildTestable(
        onLoginClick: () {
          called = true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(messages.loginButton));
    await tester.pumpAndSettle();
    expect(called, isTrue);
  });
}
