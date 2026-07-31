import 'dart:async';

import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'identity_repository.dart';
import 'session_client_provider.dart';

/// Providers for accessing the session store and state.
final identitySessionStoreProvider = AsyncNotifierProvider<IdentitySessionStore, Identity?>(
  IdentitySessionStore.new,
);

/// The auth link the app was opened with, parsed once and then fixed for the rest of the run.
///
/// It is a plain [Provider] on purpose: parsing is pure, and the URL it reads is destroyed
/// moments later (the tokens are cleared from the address bar once consumed), so a value that
/// could be recomputed would not survive its own source. First read wins, and
/// [IdentitySessionStore] makes sure that first read happens before the URL is touched.
final authLinkProvider = Provider<ZenAuthLink>((ref) => ZenAuthLink.current());

/// Whether the user still has to choose a new password before the app lets them get on with
/// anything — true from the moment a recovery link signs them in until they set one.
///
/// Recovery is the one flow where being signed in is not the end of it: the link's whole purpose
/// is the password change, and a user dropped straight onto the dashboard would leave the account
/// with the password they could not remember.
final passwordResetRequiredProvider =
    NotifierProvider<PasswordResetRequired, bool>(PasswordResetRequired.new);

/// Notifier behind [passwordResetRequiredProvider].
class PasswordResetRequired extends Notifier<bool> {
  /// Derived from the link the app was opened with, so the startup path raises the gate without
  /// anyone having to remember to. A link that arrives later — the native case — has to say so
  /// itself through [require], because the URL the app started with knew nothing about it.
  @override
  bool build() => ref.watch(authLinkProvider).requiresNewPassword;

  /// Raises the gate for a recovery link received while the app was already running.
  void require() => state = true;

  /// Lowers it: the new password has been accepted.
  void complete() => state = false;
}

/// Manages the current user session state.
class IdentitySessionStore extends AsyncNotifier<Identity?> {
  late final IdentityRepository _repository;

  @override
  FutureOr<Identity?> build() async {
    _repository = ref.watch(identityRepositoryProvider);
    // An email link is consumed BEFORE the ordinary session probe, and inside the same load the
    // app already splashes on. That ordering is the whole feature: a user arriving from a
    // confirmation link has no cookie yet, so probing first would answer "anonymous", show the
    // login screen, and only then log them in behind it — a visible flicker into a screen they
    // did not need. Exchanging first means the probe is unnecessary and the app renders once,
    // already signed in.
    final identity = await _consumeAuthLink();
    if (identity != null) return identity;

    // A persisted session is resumed BEFORE the probe, for the same reason the link is: the probe
    // asks "is there an access token?", and on a native launch there is not — only a refresh
    // token, restored from the keystore. Probing first would answer "anonymous" and show a login
    // screen to someone who never signed out.
    final resumed = await _resumePersistedSession();
    if (resumed != null) return resumed;

    final result = await _repository.getCurrentIdentity();
    return result.fold((model) => model?.toDomain(), (failure) => null);
  }

  /// Restores a stored refresh token and exchanges it for a live session.
  ///
  /// Returns null whenever there is nothing to resume, which is the ordinary case on the web (no
  /// session client is provided), on a first launch, and after a seven-day token finally expires.
  /// A refusal is not an error worth surfacing: it means "sign in again", and the login screen is
  /// already where the user is headed.
  Future<Identity?> _resumePersistedSession() async {
    final session = ref.read(sessionClientProvider);
    if (session == null) return null;

    if (!await session.restore()) return null;

    final result = await _repository.refreshSession();
    final identity = result.fold<Identity?>((model) => model.toDomain(), (_) => null);
    if (identity == null) {
      // The stored token was rejected — expired, revoked, or already rotated by another install.
      // Drop it rather than present the same dead credential on every future launch.
      await session.clear();
    }
    return identity;
  }

  /// True when an auth link was present but could not be turned into a session (expired, already
  /// used). Read by the login screen to explain why the user is looking at a login form after
  /// following a link. It is a field on the store rather than another provider because writing to
  /// one provider from inside another's initialization is exactly what Riverpod forbids.
  bool linkRejected = false;

  /// The last link token handed to [consumeAuthLink], so a platform that announces one launch URL
  /// several times does not spend it several times.
  String? _consumedToken;

  /// Exchanges an auth link's tokens for a session, if the app was opened with one. Returns the
  /// signed-in identity, or null when there was no link or it could not be used — in which case
  /// the caller falls back to the normal probe and the user signs in by hand.
  Future<Identity?> _consumeAuthLink() async {
    // Read through the provider, and do it before anything can clear the URL: the provider parses
    // `Uri.base` on first read and caches it, so this read is what freezes the landing for the
    // rest of the session. Parsing it again later would see the cleaned-up URL and conclude there
    // had never been a link.
    final link = ref.read(authLinkProvider);
    if (link.kind == ZenAuthLinkKind.failed) {
      linkRejected = true;
      return null;
    }
    if (!link.hasSession) return null;

    final result = await _repository.exchangeLinkSession(
      accessToken: link.accessToken!,
      refreshToken: link.refreshToken,
    );
    return result.fold(
      (model) {
        // The tokens are in httpOnly cookies now, so strip them from the address bar: they should
        // not sit in browser history or in a URL the user might copy, and a reload should not
        // replay a landing that has already happened.
        ZenAuthLink.clearFromUrl();
        return model.toDomain();
      },
      (failure) {
        // A refused link is not an app error; it means "sign in normally". The URL is left alone
        // because nothing was consumed.
        linkRejected = true;
        return null;
      },
    );
  }

  /// Signs in with email and password.
  Future<ZenResult<Identity>> login(String email, String password) async {
    // Do NOT flip the session to loading: a login *attempt* is an operation, not a session-state
    // transition. The app splashes on `loading` (for the initial identity fetch), and doing so
    // here would tear down the login screen mid-submit — so its post-result snackbar, guarded by
    // `mounted`, would never show, and the splash flash would read as a page reload. The screen
    // shows its own submit spinner locally.
    final result = await _repository.loginWithEmail(email: email, password: password);

    return result.fold(
      (model) {
        final identity = model.toDomain();
        state = AsyncValue.data(identity);
        return ZenResult.ok(identity);
      },
      (failure) {
        state = const AsyncValue.data(null);
        return ZenResult.err(failure);
      },
    );
  }

  /// Registers and optionally logs in.
  Future<ZenResult<Identity>> register(String email, String password) async {
    // See login(): a register attempt must not flip the session to loading, or the app splash
    // tears down the register screen and its "check your email" dialog / error snackbar never show.
    final result = await _repository.registerWithEmail(email: email, password: password);

    return result.fold(
      (model) {
        final identity = model.toDomain();
        // Only a registration that returns a session (auto-confirm) signs the user in. When email
        // confirmation is required the identity comes back unverified with no session cookie, so
        // the auth state stays unauthenticated — otherwise the app would navigate to the dashboard
        // and skip the "confirm your email" step. The register screen reads the returned identity.
        state = identity.emailVerified ? AsyncValue.data(identity) : const AsyncValue.data(null);
        return ZenResult.ok(identity);
      },
      (failure) {
        state = const AsyncValue.data(null);
        return ZenResult.err(failure);
      },
    );
  }

  /// Restores password.
  Future<ZenResult<void>> restorePassword(String email) async {
    return _repository.restorePassword(email: email);
  }

  /// Signs the user in from a link that arrived while the app was already running, and reports
  /// what the link was.
  ///
  /// The web never needs this: there, the link *is* how the app was opened, and [build] has
  /// already consumed it. A native build is the opposite — the operating system hands a running
  /// app the URL that was tapped, at any moment, and this is where that URL goes. Deep-link
  /// registration is per-platform and belongs to the application; consuming the result is the
  /// framework's job, and takes a plain [Uri] so it does not care which plugin or channel
  /// delivered it.
  ///
  /// A recovery link raises the same gate it does at startup, so a running app is not left signed
  /// in with a password its owner still cannot remember.
  Future<ZenAuthLink> consumeAuthLink(Uri uri) async {
    final link = ZenAuthLink.parse(uri);
    if (!link.hasSession) return link;

    // One link is one sign-in, however many times the platform announces it. Platforms disagree
    // about this: iOS delivers a launch URL as the initial link *and* replays it on the stream,
    // so the same token arrived three times in one cold start, while macOS delivered it once.
    // Rather than make every application discover that, the token itself is the identity of the
    // attempt — a second delivery of one already handled is dropped here.
    if (_consumedToken == link.accessToken) return link;
    _consumedToken = link.accessToken;

    final result = await _repository.exchangeLinkSession(
      accessToken: link.accessToken!,
      refreshToken: link.refreshToken,
    );
    return result.fold(
      (model) {
        state = AsyncValue.data(model.toDomain());
        if (link.requiresNewPassword) {
          // Unlike the startup path, this raises the gate by hand: passwordResetRequiredProvider
          // derives from the URL the app was *opened* with, which said nothing about a link that
          // arrived later.
          ref.read(passwordResetRequiredProvider.notifier).require();
        }
        return link;
      },
      // A spent link must not sign anyone out: whoever is using the app now is not the person the
      // stale link was for, and taking their session away would be a worse answer than ignoring it.
      (failure) => const ZenAuthLink.rejected(),
    );
  }

  /// Sets a new password for the current session, and — when this is the end of a recovery — takes
  /// the gate down. The session is unchanged either way: the user stays signed in, as they already
  /// were when they typed the new password.
  Future<ZenResult<void>> setPassword(String password) async {
    final result = await _repository.setPassword(password: password);
    return result.fold((_) {
      ref.read(passwordResetRequiredProvider.notifier).complete();
      return const ZenResult<void>.ok(null);
    }, ZenResult<void>.err);
  }

  /// Logs out.
  Future<ZenResult<void>> logout() async {
    state = const AsyncValue.loading();
    final result = await _repository.logout();

    state = const AsyncValue.data(null);
    return result;
  }
}
