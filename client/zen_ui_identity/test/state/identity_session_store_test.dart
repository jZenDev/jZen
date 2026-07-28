import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/src/state/identity_repository.dart';
import 'package:zen_ui_identity/src/state/identity_session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements IdentityRepository {
  ZenResult<IdentityContract?> getCurrentIdentityResult;
  ZenResult<IdentityContract> loginResult;
  ZenResult<IdentityContract> registerResult;
  ZenResult<void> restoreResult;
  ZenResult<void> logoutResult;
  ZenResult<IdentityContract> exchangeResult;
  ZenResult<void> setPasswordResult;

  /// Set when the ordinary session probe runs, so a test can assert it did not.
  bool probed = false;
  String? exchangedAccessToken;

  _FakeRepo({
    ZenResult<IdentityContract?>? getCurrentIdentityResult,
    ZenResult<IdentityContract>? loginResult,
    ZenResult<IdentityContract>? registerResult,
    ZenResult<void>? restoreResult,
    ZenResult<void>? logoutResult,
    ZenResult<IdentityContract>? exchangeResult,
    ZenResult<void>? setPasswordResult,
  }) : exchangeResult = exchangeResult ?? const ZenResult.err(ZenUnknownError('not set')),
       setPasswordResult = setPasswordResult ?? const ZenResult.err(ZenUnknownError('not set')),
       getCurrentIdentityResult = getCurrentIdentityResult ?? const ZenResult.ok(null),
       loginResult = loginResult ?? const ZenResult.err(ZenUnknownError('not set')),
       registerResult = registerResult ?? const ZenResult.err(ZenUnknownError('not set')),
       restoreResult = restoreResult ?? const ZenResult.err(ZenUnknownError('not set')),
       logoutResult = logoutResult ?? const ZenResult.err(ZenUnknownError('not set'));

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async {
    probed = true;
    return getCurrentIdentityResult;
  }

  @override
  Future<ZenResult<IdentityContract>> exchangeLinkSession({
    required String accessToken,
    String? refreshToken,
  }) async {
    exchangedAccessToken = accessToken;
    return exchangeResult;
  }

  @override
  Future<ZenResult<void>> setPassword({required String password}) async => setPasswordResult;

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) async => loginResult;

  @override
  Future<ZenResult<IdentityContract>> registerWithEmail({
    required String email,
    required String password,
  }) async => registerResult;

  @override
  Future<ZenResult<void>> restorePassword({required String email}) async => restoreResult;

  @override
  Future<ZenResult<void>> logout() async => logoutResult;
}

IdentityContract _makeContract(String id, {bool emailVerified = true}) => IdentityContract(
  id: id,
  lifecycle: IdentityLifecycleContract(state: IdentityState.active.name),
  authority: const AuthorityContract(roles: [], capabilities: []),
  createdAt: DateTime.now().millisecondsSinceEpoch,
  emailVerified: emailVerified,
);

void main() {
  test('build sets initial session from repository', () async {
    final fake = _FakeRepo(getCurrentIdentityResult: ZenResult.ok(_makeContract('sub')));
    final container = ProviderContainer(
      overrides: [identityRepositoryProvider.overrideWithValue(fake)],
    );

    final value = await container.read(identitySessionStoreProvider.future);
    expect(value, isNotNull);
    expect(value?.id.value, 'sub');
  });

  test('login success updates state and returns ok', () async {
    final contract = _makeContract('u1');
    final fake = _FakeRepo(
      getCurrentIdentityResult: const ZenResult.ok(null),
      loginResult: ZenResult.ok(contract),
      logoutResult: const ZenResult.ok(null),
    );

    final container = ProviderContainer(
      overrides: [identityRepositoryProvider.overrideWithValue(fake)],
    );
    final notifier = container.read(identitySessionStoreProvider.notifier);

    final res = await notifier.login('a@b.com', 'pw');
    expect(res.isSuccess, true);
    final current = container.read(identitySessionStoreProvider);
    expect(current.asData?.value?.id.value, 'u1');

    // logout clears state
    final out = await notifier.logout();
    expect(out.isSuccess, true);
    final after = container.read(identitySessionStoreProvider);
    expect(after.asData?.value, isNull);
  });

  test('login failure returns error and leaves state null', () async {
    final fake = _FakeRepo(
      getCurrentIdentityResult: const ZenResult.ok(null),
      loginResult: const ZenResult.err(ZenValidationError('bad')),
    );

    final container = ProviderContainer(
      overrides: [identityRepositoryProvider.overrideWithValue(fake)],
    );
    final notifier = container.read(identitySessionStoreProvider.notifier);

    final res = await notifier.login('a@b.com', 'pw');
    expect(res.isFailure, true);
    final current = container.read(identitySessionStoreProvider);
    expect(current.asData?.value, isNull);
  });

  test('register mirrors login behavior', () async {
    final contract = _makeContract('r1');
    final fake = _FakeRepo(
      getCurrentIdentityResult: const ZenResult.ok(null),
      registerResult: ZenResult.ok(contract),
    );

    final container = ProviderContainer(
      overrides: [identityRepositoryProvider.overrideWithValue(fake)],
    );
    final notifier = container.read(identitySessionStoreProvider.notifier);

    final res = await notifier.register('x@y.com', 'pw');
    expect(res.isSuccess, true);
    final current = container.read(identitySessionStoreProvider);
    expect(current.asData?.value?.id.value, 'r1');
  });

  test('register requiring email confirmation does not authenticate', () async {
    // An unverified registration (202, no session) must leave the session unauthenticated, so the
    // app does not navigate to the dashboard before the user confirms and logs in.
    final contract = _makeContract('r2', emailVerified: false);
    final fake = _FakeRepo(
      getCurrentIdentityResult: const ZenResult.ok(null),
      registerResult: ZenResult.ok(contract),
    );

    final container = ProviderContainer(
      overrides: [identityRepositoryProvider.overrideWithValue(fake)],
    );
    final notifier = container.read(identitySessionStoreProvider.notifier);

    final res = await notifier.register('x@y.com', 'pw');
    // The call succeeds and returns the (unverified) identity...
    expect(res.isSuccess, true);
    expect(res.fold((i) => i.emailVerified, (_) => true), false);
    // ...but the session state stays unauthenticated.
    final current = container.read(identitySessionStoreProvider);
    expect(current.asData?.value, isNull);
  });

  test('a confirmation link signs the user in instead of probing for a session', () async {
    // The point of the feature: arriving from an email link must not first answer "anonymous".
    final fake = _FakeRepo(exchangeResult: ZenResult.ok(_makeContract('confirmed')));
    final container = ProviderContainer(
      overrides: [
        identityRepositoryProvider.overrideWithValue(fake),
        authLinkProvider.overrideWithValue(
          ZenAuthLink.parse(Uri.parse('https://app/#access_token=at&refresh_token=rt&type=signup')),
        ),
      ],
    );

    final value = await container.read(identitySessionStoreProvider.future);
    expect(value?.id.value, 'confirmed');
    expect(fake.exchangedAccessToken, 'at');
    expect(fake.probed, false, reason: 'the exchange already established the session');
  });

  test('a spent link falls back to the login screen and is recorded', () async {
    final fake = _FakeRepo(
      exchangeResult: const ZenResult.err(ZenUnauthorizedError('expired')),
      getCurrentIdentityResult: const ZenResult.ok(null),
    );
    final container = ProviderContainer(
      overrides: [
        identityRepositoryProvider.overrideWithValue(fake),
        authLinkProvider.overrideWithValue(
          ZenAuthLink.parse(Uri.parse('https://app/#access_token=stale&type=signup')),
        ),
      ],
    );

    final value = await container.read(identitySessionStoreProvider.future);
    expect(value, isNull);
    expect(fake.probed, true, reason: 'a refused link must not skip the normal session probe');
    expect(container.read(identitySessionStoreProvider.notifier).linkRejected, true);
  });

  test('a recovery link holds the password gate up until a new password is set', () async {
    final fake = _FakeRepo(
      exchangeResult: ZenResult.ok(_makeContract('recovering')),
      setPasswordResult: const ZenResult.ok(null),
    );
    final container = ProviderContainer(
      overrides: [
        identityRepositoryProvider.overrideWithValue(fake),
        authLinkProvider.overrideWithValue(
          ZenAuthLink.parse(Uri.parse('https://app/#access_token=at&type=recovery')),
        ),
      ],
    );

    final value = await container.read(identitySessionStoreProvider.future);
    expect(value?.id.value, 'recovering', reason: 'recovery signs in; that is what authorizes it');
    expect(container.read(passwordResetRequiredProvider), true);

    final res = await container.read(identitySessionStoreProvider.notifier).setPassword('new-pw');
    expect(res.isSuccess, true);
    expect(container.read(passwordResetRequiredProvider), false);
  });

  test('restorePassword returns result from repo', () async {
    final fakeOk = _FakeRepo(restoreResult: const ZenResult.ok(null));
    final containerOk = ProviderContainer(
      overrides: [identityRepositoryProvider.overrideWithValue(fakeOk)],
    );
    final notifierOk = containerOk.read(identitySessionStoreProvider.notifier);
    final ok = await notifierOk.restorePassword('a@b.com');
    expect(ok.isSuccess, true);

    final fakeErr = _FakeRepo(restoreResult: const ZenResult.err(ZenNotFoundError('no')));
    final containerErr = ProviderContainer(
      overrides: [identityRepositoryProvider.overrideWithValue(fakeErr)],
    );
    final notifierErr = containerErr.read(identitySessionStoreProvider.notifier);
    final err = await notifierErr.restorePassword('a@b.com');
    expect(err.isFailure, true);
  });
}
