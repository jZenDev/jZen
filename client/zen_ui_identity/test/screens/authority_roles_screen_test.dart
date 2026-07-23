import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/src/screens/authority_roles_screen.dart';
import 'package:zen_ui_identity/src/state/identity_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/localized_app.dart';

class _FakeRepo implements IdentityRepository {
  ZenResult<IdentityContract?> current;
  _FakeRepo({ZenResult<IdentityContract?>? current})
    : current = current ?? const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async => current;

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('no'));

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

void main() {

  testWidgets('shows unauthenticated when no identity', (tester) async {
    final repo = _FakeRepo(current: const ZenResult.ok(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(
          home: AuthorityRolesScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Not authenticated'), findsOneWidget);
  });

  testWidgets('shows no roles when empty', (tester) async {
    final contract = IdentityContract(
      id: 'user-1',
      lifecycle: const IdentityLifecycleContract(state: 'active'),
      authority: const AuthorityContract(roles: [], capabilities: []),
      createdAt: ZenTimestamp.now().millisecondsSinceEpoch,
    );

    final repo = _FakeRepo(current: ZenResult.ok(contract));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(
          home: AuthorityRolesScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('No roles assigned'), findsOneWidget);
  });

  testWidgets('renders roles cards when present', (tester) async {
    final contract = IdentityContract(
      id: 'user-2',
      lifecycle: const IdentityLifecycleContract(state: 'active'),
      authority: const AuthorityContract(roles: ['ADMIN'], capabilities: []),
      createdAt: ZenTimestamp.now().millisecondsSinceEpoch,
    );

    final repo = _FakeRepo(current: ZenResult.ok(contract));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: localizedApp(
          home: AuthorityRolesScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('ADMIN'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
  });
}
