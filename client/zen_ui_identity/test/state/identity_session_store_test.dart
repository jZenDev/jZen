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

  _FakeRepo({
    ZenResult<IdentityContract?>? getCurrentIdentityResult,
    ZenResult<IdentityContract>? loginResult,
    ZenResult<IdentityContract>? registerResult,
    ZenResult<void>? restoreResult,
    ZenResult<void>? logoutResult,
  }) : getCurrentIdentityResult = getCurrentIdentityResult ?? const ZenResult.ok(null),
       loginResult = loginResult ?? const ZenResult.err(ZenUnknownError('not set')),
       registerResult = registerResult ?? const ZenResult.err(ZenUnknownError('not set')),
       restoreResult = restoreResult ?? const ZenResult.err(ZenUnknownError('not set')),
       logoutResult = logoutResult ?? const ZenResult.err(ZenUnknownError('not set'));

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async => getCurrentIdentityResult;

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

IdentityContract _makeContract(String id) => IdentityContract(
  id: id,
  lifecycle: IdentityLifecycleContract(state: IdentityState.active.name),
  authority: const AuthorityContract(roles: [], capabilities: []),
  createdAt: DateTime.now().millisecondsSinceEpoch,
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
