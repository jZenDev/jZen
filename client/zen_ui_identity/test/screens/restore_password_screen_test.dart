import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/src/screens/restore_password_screen.dart';
import 'package:zen_ui_identity/src/state/identity_repository.dart';
import 'package:zen_ui_identity/src/theme/identity_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/localized_app.dart';

class _FakeRepo implements IdentityRepository {
  ZenResult<void> restoreResult;
  _FakeRepo({ZenResult<void>? restoreResult})
    : restoreResult = restoreResult ?? const ZenResult.err(ZenUnknownError('not set'));

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async => const ZenResult.ok(null);

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
  Future<ZenResult<void>> restorePassword({required String email}) async => restoreResult;

  @override
  Future<ZenResult<void>> logout() async => const ZenResult.err(ZenUnknownError('not implemented'));
}

void main() {
  testWidgets('success shows success snackbar and calls callback', (tester) async {
    final repo = _FakeRepo(restoreResult: const ZenResult.ok(null));
    var called = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(home: RestorePasswordScreen(onRestoreSuccess: () => called = true)),
      ),
    );

    await tester.pumpAndSettle();

    // enter a valid email
    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.tap(find.text('Send Link'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Reset link sent to your email'), findsOneWidget);
    expect(called, isTrue);
  });

  testWidgets('error shows error snackbar with error color', (tester) async {
    final repo = _FakeRepo(restoreResult: const ZenResult.err(ZenNotFoundError('no')));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(home: RestorePasswordScreen()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.tap(find.text('Send Link'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Requested resource not found.'), findsOneWidget);

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.backgroundColor, IdentityThemeExtension.fallback().errorColor);
  });
}
