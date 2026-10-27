import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_demo_client/src/demo_root.dart';
import 'package:zen_demo_client/src/l10n/generated/demo_localizations.dart';
import 'package:zen_demo_client/src/screens/auth_flow.dart';
import 'package:zen_demo_client/src/screens/home_shell.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

class _ConfirmingRepository implements IdentityRepository {
  String? confirmedHash;
  String? confirmedType;

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async => const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract>> confirmEmailLink({
    required String tokenHash,
    required String type,
  }) async {
    confirmedHash = tokenHash;
    confirmedType = type;
    return ZenResult.ok(_identity());
  }

  @override
  Future<ZenResult<IdentityContract>> exchangeLinkSession({
    required String accessToken,
    String? refreshToken,
  }) async => const ZenResult.err(ZenUnknownError('legacy exchange not used'));

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('login not used'));

  @override
  Future<ZenResult<IdentityContract>> registerWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('register not used'));

  @override
  Future<ZenResult<void>> restorePassword({required String email}) async =>
      const ZenResult.err(ZenUnknownError('recovery request not used'));

  @override
  Future<ZenResult<void>> setPassword({required String password, String? currentPassword}) async =>
      const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract>> refreshSession() async =>
      const ZenResult.err(ZenUnknownError('refresh not used'));

  @override
  Future<ZenResult<void>> logout() async => const ZenResult.ok(null);

  IdentityContract _identity() => IdentityContract(
    id: 'verified-user',
    lifecycle: const IdentityLifecycleContract(state: 'active'),
    authority: const AuthorityContract(roles: ['user']),
    createdAt: 1,
    emailVerified: true,
  );
}

void main() {
  Future<void> pumpAuthLink(WidgetTester tester, String tokenHash, String type) async {
    final repository = _ConfirmingRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          identityRepositoryProvider.overrideWithValue(repository),
          authLinkProvider.overrideWithValue(
            ZenAuthLink.parse(
              Uri.parse('https://demo.example.com/?token_hash=$tokenHash&type=$type'),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            ...DemoLocalizations.localizationsDelegates,
            identityLocaleDelegate,
            navigationLocaleDelegate,
          ],
          supportedLocales: DemoLocalizations.supportedLocales,
          home: const DemoRoot(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.confirmedHash, tokenHash);
    expect(repository.confirmedType, type);
  }

  testWidgets('signup hand-off signs in to the zen_demo home shell', (tester) async {
    await pumpAuthLink(tester, 'signup-hash', 'signup');

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(AuthFlow), findsNothing);
  });

  testWidgets('recovery hand-off signs in behind the new-password gate', (tester) async {
    await pumpAuthLink(tester, 'recovery-hash', 'recovery');

    expect(find.byType(SetPasswordScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });
}
