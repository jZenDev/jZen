import 'dart:async';

import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'identity_repository.dart';

/// Providers for accessing the session store and state.
final identitySessionStoreProvider = AsyncNotifierProvider<IdentitySessionStore, Identity?>(
  IdentitySessionStore.new,
);

/// Manages the current user session state.
class IdentitySessionStore extends AsyncNotifier<Identity?> {
  late final IdentityRepository _repository;

  @override
  FutureOr<Identity?> build() async {
    _repository = ref.watch(identityRepositoryProvider);
    // Initial load
    final result = await _repository.getCurrentIdentity();
    return result.fold((model) => model?.toDomain(), (failure) => null);
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

  /// Logs out.
  Future<ZenResult<void>> logout() async {
    state = const AsyncValue.loading();
    final result = await _repository.logout();

    state = const AsyncValue.data(null);
    return result;
  }
}
