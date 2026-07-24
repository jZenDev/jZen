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
    state = const AsyncValue.loading();
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
    state = const AsyncValue.loading();
    final result = await _repository.registerWithEmail(email: email, password: password);

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
