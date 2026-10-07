import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/src/screens/restore_password_screen.dart';
import 'package:zen_ui_identity/src/state/identity_repository.dart';
import 'package:zen_ui_identity/src/theme/identity_theme_extension.dart';
import 'package:flutter/cupertino.dart';
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
  Future<ZenResult<void>> logout() async => const ZenResult.err(ZenUnknownError('not implemented'));
}

void main() {
  testWidgets('success shows the success message and calls callback', (tester) async {
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
    await tester.enterText(find.byType(EditableText), 'user@example.com');
    await tester.tap(find.text('Send Link'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Reset link sent to your email'), findsOneWidget);
    expect(called, isTrue);
  });

  testWidgets('rejects an email that only contains an @ sign', (tester) async {
    final repo = _FakeRepo(restoreResult: const ZenResult.ok(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(home: RestorePasswordScreen()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), 'a@');
    await tester.tap(find.text('Send Link'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Invalid email'), findsOneWidget);
  });

  testWidgets('error shows the message in the error colour', (tester) async {
    final repo = _FakeRepo(restoreResult: const ZenResult.err(ZenNotFoundError('no')));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(home: RestorePasswordScreen()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), 'user@example.com');
    await tester.tap(find.text('Send Link'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Requested resource not found.'), findsOneWidget);

    // The message is a snack bar on Material and a toast on Apple; both paint it on a Material.
    final surface = tester.widget<Material>(
      find
          .ancestor(of: find.text('Requested resource not found.'), matching: find.byType(Material))
          .first,
    );
    expect(surface.color, IdentityThemeExtension.fallback().errorColor);
  });

  testWidgets('the top bar is the platform idiom: Cupertino on Apple, Material elsewhere', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          identityRepositoryProvider.overrideWithValue(
            _FakeRepo(restoreResult: const ZenResult.ok(null)),
          ),
        ],
        child: localizedApp(home: RestorePasswordScreen(onBackClick: () {})),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoNavigationBar), zenIsApplePlatform ? findsOneWidget : findsNothing);
    expect(find.byType(AppBar), zenIsApplePlatform ? findsNothing : findsOneWidget);
    expect(find.text('Reset Password'), findsOneWidget);
  });

  testWidgets('the back control is a labelled button that calls onBackClick', (tester) async {
    final semantics = tester.ensureSemantics();
    var backs = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          identityRepositoryProvider.overrideWithValue(
            _FakeRepo(restoreResult: const ZenResult.ok(null)),
          ),
        ],
        child: localizedApp(home: RestorePasswordScreen(onBackClick: () => backs++)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    expect(backs, 1);
    semantics.dispose();
  });
}
