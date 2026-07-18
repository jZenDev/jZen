import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_localization/zen_localization.dart';
import 'package:zen_ui_identity/src/l10n/identity_messages.dart';
import 'package:zen_ui_identity/src/screens/profile_screen.dart';
import 'package:zen_ui_identity/src/state/identity_repository.dart';
import 'package:zen_ui_identity/src/theme/identity_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements IdentityRepository {
  ZenResult<IdentityContract?> current;
  ZenResult<void> logoutResult;
  _FakeRepo({
    ZenResult<IdentityContract?>? current,
    ZenResult<void>? logoutResult,
  }) : current = current ?? const ZenResult.ok(null),
       logoutResult = logoutResult ?? const ZenResult.ok(null);

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
  Future<ZenResult<void>> logout() async => logoutResult;
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const en = 'en';
  final msgs = IdentityMessages(
    _FakeLocalization({
      'profile.title': 'Profile',
      'not.authenticated': 'Not Auth',
      'roles.label': 'Roles',
      'logout.button': 'Logout',
      'profile.avatar.label': 'Avatar',
      'back.button.tooltip': 'Back',
    }),
    en,
  );

  testWidgets('shows not authenticated when no identity', (tester) async {
    final repo = _FakeRepo(current: const ZenResult.ok(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: ThemeData(extensions: [IdentityThemeExtension.fallback()]),
          home: ProfileScreen(messages: msgs),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Not Auth'), findsOneWidget);
  });

  testWidgets('displays profile and calls logout callback', (tester) async {
    final contract = IdentityContract(
      id: 'user-1',
      lifecycle: const IdentityLifecycleContract(state: 'active'),
      authority: const AuthorityContract(roles: ['ADMIN']),
      createdAt: ZenTimestamp.now().millisecondsSinceEpoch,
    );

    var called = false;
    Identity? logoutIdentity;
    final repo = _FakeRepo(
      current: ZenResult.ok(contract),
      logoutResult: const ZenResult.ok(null),
    );

    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: ThemeData(extensions: [IdentityThemeExtension.fallback()]),
          home: ProfileScreen(
            messages: msgs,
            onLogoutSuccess: () => called = true,
            onLogoutSuccessWithIdentity: (id) => logoutIdentity = id,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('user-1'), findsOneWidget);
    expect(find.text('ADMIN'), findsOneWidget);

    // Check Semantics
    expect(
      tester.getSemantics(find.byTooltip('Logout').first).tooltip,
      contains('Logout'),
    );
    expect(
      tester.getSemantics(find.byType(CircleAvatar)).label,
      contains('Avatar'),
    );

    await tester.tap(find.byIcon(Icons.logout).first);
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(logoutIdentity?.id.value, 'user-1');

    semantics.dispose();
  });
}
