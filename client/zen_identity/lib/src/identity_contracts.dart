import 'package:zen_core/zen_core.dart';
import 'package:meta/meta.dart';

import 'identity_models.dart';

/// Serializable representation of Authority.
@immutable
final class AuthorityContract {
  /// The roles assigned to the identity.
  final List<String> roles;

  /// The explicit capabilities granted to the identity.
  final List<String> capabilities;

  /// Creates an [AuthorityContract].
  const AuthorityContract({this.roles = const [], this.capabilities = const []});

  /// Maps [Authority] domain model to [AuthorityContract].
  factory AuthorityContract.fromDomain(Authority authority) => AuthorityContract(
    roles: authority.roles.map((r) => r.name).toList(),
    capabilities: authority.capabilities.map((c) => c.id).toList(),
  );

  /// Maps [AuthorityContract] to [Authority] domain model.
  Authority toDomain() => Authority(
    roles: roles.map(Role.reconstruct).toSet(),
    capabilities: capabilities.map(Capability.reconstruct).toSet(),
  );

  /// Creates [AuthorityContract] from JSON.
  factory AuthorityContract.fromJson(Map<String, dynamic> json) => AuthorityContract(
    roles: List<String>.from(json['roles'] as Iterable? ?? []),
    capabilities: List<String>.from(json['capabilities'] as Iterable? ?? []),
  );

  /// Converts this [AuthorityContract] to JSON.
  Map<String, dynamic> toJson() => {'roles': roles, 'capabilities': capabilities};
}

/// Serializable representation of IdentityLifecycle.
@immutable
final class IdentityLifecycleContract {
  /// The current state name.
  final String state;

  /// The reason for the current state.
  final String? reason;

  /// Creates an [IdentityLifecycleContract].
  const IdentityLifecycleContract({required this.state, this.reason});

  /// Maps [IdentityLifecycle] domain model to [IdentityLifecycleContract].
  factory IdentityLifecycleContract.fromDomain(IdentityLifecycle lifecycle) =>
      IdentityLifecycleContract(state: lifecycle.state.name, reason: lifecycle.reason);

  /// Maps [IdentityLifecycleContract] to [IdentityLifecycle] domain model.
  IdentityLifecycle toDomain() => IdentityLifecycle.reconstruct(
    IdentityState.values.firstWhere((s) => s.name == state, orElse: () => IdentityState.pending),
    reason,
  );

  /// Creates [IdentityLifecycleContract] from JSON.
  factory IdentityLifecycleContract.fromJson(Map<String, dynamic> json) =>
      IdentityLifecycleContract(state: json['state'] as String, reason: json['reason'] as String?);

  /// Converts this [IdentityLifecycleContract] to JSON.
  Map<String, dynamic> toJson() => {'state': state, if (reason != null) 'reason': reason};
}

/// Serializable representation of Identity.
@immutable
final class IdentityContract {
  /// The unique identifier.
  final String id;

  /// The current lifecycle state.
  final IdentityLifecycleContract lifecycle;

  /// The authority context.
  final AuthorityContract authority;

  /// When the identity was created.
  final int createdAt;

  /// Whether the account's email is confirmed. False on a registration that requires email
  /// confirmation: the account exists but there is no session yet, so the caller shows a
  /// "check your email" state rather than treating the identity as signed in.
  final bool emailVerified;

  /// Creates an [IdentityContract].
  const IdentityContract({
    required this.id,
    required this.lifecycle,
    required this.authority,
    required this.createdAt,
    this.emailVerified = false,
  });

  /// Maps [Identity] domain aggregate to [IdentityContract].
  factory IdentityContract.fromDomain(Identity identity) => IdentityContract(
    id: identity.id.value,
    lifecycle: IdentityLifecycleContract.fromDomain(identity.lifecycle),
    authority: AuthorityContract.fromDomain(identity.authority),
    createdAt: identity.createdAt.millisecondsSinceEpoch,
    emailVerified: identity.emailVerified,
  );

  /// Maps [IdentityContract] to [Identity] domain aggregate.
  Identity toDomain() => Identity(
    id: IdentityId.reconstruct(id),
    lifecycle: lifecycle.toDomain(),
    authority: authority.toDomain(),
    createdAt: ZenTimestamp.fromMilliseconds(createdAt),
    emailVerified: emailVerified,
  );

  /// Creates [IdentityContract] from JSON.
  factory IdentityContract.fromJson(Map<String, dynamic> json) => IdentityContract(
    id: json['id'] as String,
    lifecycle: IdentityLifecycleContract.fromJson(json['lifecycle'] as Map<String, dynamic>),
    authority: AuthorityContract.fromJson(json['authority'] as Map<String, dynamic>),
    createdAt: json['createdAt'] as int,
  );

  /// Converts this [IdentityContract] to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'lifecycle': lifecycle.toJson(),
    'authority': authority.toJson(),
    'createdAt': createdAt,
  };
}

/// Interface for identity operations, typically implemented by infrastructure.
abstract class IdentityRepository {
  /// Retrieves the current authenticated identity, if any.
  Future<ZenResult<IdentityContract?>> getCurrentIdentity();

  /// Authenticates with email and password.
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  });

  /// Registers a new identity with email and password.
  Future<ZenResult<IdentityContract>> registerWithEmail({
    required String email,
    required String password,
  });

  /// Triggers a password recovery flow.
  Future<ZenResult<void>> restorePassword({required String email});

  /// Exchanges the tokens a confirmation or recovery email link delivered for a real session.
  ///
  /// The tokens arrive in the URL fragment, which no server can see, so handing them back is the
  /// client's job — see `ZenAuthLink`. The implementation must not trust them itself: it posts
  /// them and lets the backend validate them with the identity provider before a session exists.
  Future<ZenResult<IdentityContract>> exchangeLinkSession({
    required String accessToken,
    String? refreshToken,
  });

  /// Sets a new password for the current session — the last step of password recovery, and the
  /// same call an already signed-in user makes to change their password.
  Future<ZenResult<void>> setPassword({required String password});

  /// Terminates the current session.
  Future<ZenResult<void>> logout();
}
