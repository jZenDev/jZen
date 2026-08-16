// The warm-link path: a link the operating system hands an app that is ALREADY RUNNING.
//
// This is where the gap was. A refused warm link deliberately changes nothing -- it must not sign
// out whoever is using the app now -- and "changes nothing" meant no screen had anything to react
// to, so the user tapped a link in their email and the app did not so much as blink. The startup
// path was covered (the login screen reads the outcome as it builds); this one was not covered by
// anything, which is exactly why it stayed broken.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

/// A minimal stand-in: only the calls the warm-link path makes are meaningful here.
class _FakeRepo implements IdentityRepository {
  _FakeRepo({this.exchangeResult, this.getCurrentIdentityResult});

  final ZenResult<IdentityContract>? exchangeResult;
  final ZenResult<IdentityContract?>? getCurrentIdentityResult;

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async =>
      getCurrentIdentityResult ?? const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract>> exchangeLinkSession({
    required String accessToken,
    String? refreshToken,
  }) async => exchangeResult ?? const ZenResult.err(ZenUnknownError('not set'));

  @override
  Future<ZenResult<IdentityContract>> refreshSession() async =>
      const ZenResult.err(ZenUnknownError('not stubbed'));

  @override
  Future<ZenResult<void>> setPassword({required String password}) async => const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('not stubbed'));

  @override
  Future<ZenResult<IdentityContract>> registerWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('not stubbed'));

  @override
  Future<ZenResult<void>> restorePassword({required String email}) async =>
      const ZenResult.err(ZenUnknownError('not stubbed'));

  @override
  Future<ZenResult<void>> logout() async => const ZenResult.ok(null);
}

IdentityContract makeContract(String id) => IdentityContract(
  id: id,
  lifecycle: IdentityLifecycleContract(state: IdentityState.active.name),
  authority: const AuthorityContract(roles: [], capabilities: []),
  createdAt: DateTime.now().millisecondsSinceEpoch,
  emailVerified: true,
);

void main() {
  ProviderContainer containerWith(IdentityRepository repo) {
    final c = ProviderContainer(
      overrides: [
        identityRepositoryProvider.overrideWithValue(repo),
        // No link at startup: every case here arrives afterwards.
        authLinkProvider.overrideWithValue(ZenAuthLink.parse(Uri.parse('https://app/'))),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('nothing is reported before any link arrives', () {
    final c = containerWith(_FakeRepo());
    expect(c.read(authLinkOutcomeProvider), isNull);
  });

  test('a refused warm link is reported', () async {
    final c = containerWith(
      _FakeRepo(exchangeResult: const ZenResult.err(ZenUnauthorizedError('expired'))),
    );
    await c.read(identitySessionStoreProvider.future);

    await c
        .read(identitySessionStoreProvider.notifier)
        .consumeAuthLink(Uri.parse('zendemo://auth-callback#access_token=stale&type=signup'));

    final reported = c.read(authLinkOutcomeProvider);
    expect(reported, isNotNull, reason: 'a silent refusal is the defect this covers');
    expect(reported!.kind, ZenAuthLinkKind.failed);
  });

  test('a refused warm link does not sign the current user out', () async {
    final c = containerWith(
      _FakeRepo(
        exchangeResult: const ZenResult.err(ZenUnauthorizedError('expired')),
        getCurrentIdentityResult: ZenResult.ok(makeContract('someone')),
      ),
    );
    final before = await c.read(identitySessionStoreProvider.future);
    expect(before, isNotNull);

    await c
        .read(identitySessionStoreProvider.notifier)
        .consumeAuthLink(Uri.parse('zendemo://auth-callback#access_token=stale&type=signup'));

    // Reporting the refusal must not have cost the session: the stale link was for someone else.
    expect(c.read(identitySessionStoreProvider).value?.id, before!.id);
  });

  test('a link Supabase itself refused is reported', () async {
    final c = containerWith(_FakeRepo());
    await c.read(identitySessionStoreProvider.future);

    // No token at all, just an error in the fragment -- there is nothing to exchange, so this
    // returns before the repository is touched and would otherwise vanish entirely.
    await c
        .read(identitySessionStoreProvider.notifier)
        .consumeAuthLink(
          Uri.parse('zendemo://auth-callback#error=access_denied&error_code=otp_expired'),
        );

    expect(c.read(authLinkOutcomeProvider)?.kind, ZenAuthLinkKind.failed);
  });

  test('a successful warm link reports nothing, because signing in is its own message', () async {
    final c = containerWith(_FakeRepo(exchangeResult: ZenResult.ok(makeContract('welcomed'))));
    await c.read(identitySessionStoreProvider.future);

    await c
        .read(identitySessionStoreProvider.notifier)
        .consumeAuthLink(Uri.parse('zendemo://auth-callback#access_token=good&type=signup'));

    expect(c.read(authLinkOutcomeProvider), isNull);
    expect(c.read(identitySessionStoreProvider).value?.id.toString(), contains('welcomed'));
  });

  test('an ordinary deep link is not this feature\'s business', () async {
    final c = containerWith(_FakeRepo());
    await c.read(identitySessionStoreProvider.future);

    await c
        .read(identitySessionStoreProvider.notifier)
        .consumeAuthLink(Uri.parse('zendemo://some/other/route'));

    expect(c.read(authLinkOutcomeProvider), isNull);
  });

  test('clear() stops the message repeating on a rebuild', () async {
    final c = containerWith(
      _FakeRepo(exchangeResult: const ZenResult.err(ZenUnauthorizedError('expired'))),
    );
    await c.read(identitySessionStoreProvider.future);
    await c
        .read(identitySessionStoreProvider.notifier)
        .consumeAuthLink(Uri.parse('zendemo://auth-callback#access_token=stale&type=signup'));
    expect(c.read(authLinkOutcomeProvider), isNotNull);

    c.read(authLinkOutcomeProvider.notifier).clear();
    expect(c.read(authLinkOutcomeProvider), isNull);
  });

  test('one link is reported once, however often the platform announces it', () async {
    final c = containerWith(
      _FakeRepo(exchangeResult: const ZenResult.err(ZenUnauthorizedError('expired'))),
    );
    await c.read(identitySessionStoreProvider.future);
    final store = c.read(identitySessionStoreProvider.notifier);
    final uri = Uri.parse('zendemo://auth-callback#access_token=stale&type=signup');

    await store.consumeAuthLink(uri);
    c.read(authLinkOutcomeProvider.notifier).clear();
    // iOS delivers a launch URL more than once; the dedupe must cover the report too, or the
    // second delivery raises a second snackbar for one tap.
    await store.consumeAuthLink(uri);

    expect(c.read(authLinkOutcomeProvider), isNull);
  });
}
