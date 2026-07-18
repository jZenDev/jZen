import 'package:zen_core/zen_core.dart';
import 'package:meta/meta.dart';

/// A stable, unique domain identifier for an identity.
@immutable
final class IdentityId {
  /// The underlying value of the identity identifier.
  final String value;
  const IdentityId._(this.value);

  /// Creates and validates an [IdentityId].
  static ZenResult<IdentityId> create(String value) {
    if (value.trim().isEmpty) {
      return const ZenResult.err(
        ZenValidationError('IdentityId cannot be empty'),
      );
    }
    return ZenResult.ok(IdentityId._(value));
  }

  @override
  String toString() => value;
  @override
  bool operator ==(Object other) => other is IdentityId && other.value == value;
  @override
  int get hashCode => value.hashCode;

  /// Internal: reconstructs from trusted string value.
  @internal
  const IdentityId.reconstruct(this.value);
}

/// A coarse-grained semantic grouping of permissions.
@immutable
final class Role {
  /// The unique name of the role (e.g. 'ADMIN', 'MEMBER').
  final String name;

  /// Private constructor for [Role].
  const Role._(this.name);

  /// Creates and validates a [Role].
  ///
  /// Name must be alphanumeric, between 3 and 32 characters.
  static ZenResult<Role> create(String name) {
    if (name.length < 3 || name.length > 32) {
      return const ZenResult.err(
        ZenValidationError('Role name must be between 3 and 32 characters'),
      );
    }
    if (!RegExp(r'^[A-Z0-9_]+$').hasMatch(name)) {
      return const ZenResult.err(
        ZenValidationError('Role name must be uppercase alphanumeric or "_"'),
      );
    }
    return ZenResult.ok(Role._(name));
  }

  /// Internal: reconstructs from trusted string value.
  @internal
  const Role.reconstruct(this.name);

  /// Predefined admin role.
  static const Role admin = Role._('ADMIN');

  /// Predefined user role.
  static const Role user = Role._('USER');

  @override
  bool operator ==(Object other) => other is Role && other.name == name;
  @override
  int get hashCode => name.hashCode;
  @override
  String toString() => 'Role($name)';
}

/// A fine-grained domain permission.
@immutable
final class Capability {
  /// The unique identifier for the capability (e.g. 'can_edit_document').
  final String id;

  /// Private constructor for [Capability].
  const Capability._(this.id);

  /// Creates and validates a [Capability].
  ///
  /// ID must be lowercase alphanumeric with snake_case, between 3 and 64 characters.
  static ZenResult<Capability> create(String id) {
    if (id.length < 3 || id.length > 64) {
      return const ZenResult.err(
        ZenValidationError('Capability ID must be between 3 and 64 characters'),
      );
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(id)) {
      return const ZenResult.err(
        ZenValidationError(
          'Capability ID must be lowercase alphanumeric or "_"',
        ),
      );
    }
    return ZenResult.ok(Capability._(id));
  }

  /// Internal: reconstructs from trusted string value.
  @internal
  const Capability.reconstruct(this.id);

  @override
  bool operator ==(Object other) => other is Capability && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => 'Capability($id)';
}

/// Encapsulates the roles and capabilities granted to an identity.
@immutable
final class Authority {
  /// The roles assigned to the identity.
  final Set<Role> roles;

  /// The explicit capabilities granted to the identity.
  final Set<Capability> capabilities;

  /// Creates an [Authority] context with [roles] and [capabilities].
  const Authority({this.roles = const {}, this.capabilities = const {}});

  /// Evaluates if the authority possesses the required capability.
  bool hasCapability(Capability capability) =>
      capabilities.contains(capability);

  /// Evaluates if the authority possesses any of the required roles.
  bool hasRole(Role role) => roles.contains(role);

  @override
  bool operator ==(Object other) =>
      other is Authority &&
      _setEquals(roles, other.roles) &&
      _setEquals(capabilities, other.capabilities);

  @override
  int get hashCode => Object.hashAll(roles) ^ Object.hashAll(capabilities);

  bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}

/// Represents the stable lifecycle states of an identity.
enum IdentityState {
  /// Identity exists but is not yet fully activated.
  pending,

  /// Identity is valid and may participate in domain actions.
  active,

  /// Identity exists historically but is no longer allowed to act.
  revoked,

  /// Identity is temporarily restricted from acting.
  disabled;

  /// Returns true if the identity can perform domain actions.
  bool get canAct => this == IdentityState.active;
}

/// Domain-driven lifecycle rules for identity state transitions.
@immutable
final class IdentityLifecycle {
  /// The current state of the identity.
  final IdentityState state;

  /// The reason for the current state (e.g. revocation reason).
  final String? reason;

  const IdentityLifecycle._(this.state, [this.reason]);

  /// Creates an initial [IdentityState.pending] lifecycle.
  factory IdentityLifecycle.initial() =>
      const IdentityLifecycle._(IdentityState.pending);

  /// Transitions to [IdentityState.active] state.
  ZenResult<IdentityLifecycle> activate() {
    if (state == IdentityState.revoked) {
      return const ZenResult.err(ZenUnauthorizedError('Identity is revoked'));
    }
    return const ZenResult.ok(IdentityLifecycle._(IdentityState.active));
  }

  /// Transitions to [IdentityState.revoked] state.
  ZenResult<IdentityLifecycle> revoke(String reason) {
    if (reason.trim().isEmpty) {
      return const ZenResult.err(
        ZenValidationError('Revocation reason cannot be empty'),
      );
    }
    return ZenResult.ok(IdentityLifecycle._(IdentityState.revoked, reason));
  }

  /// Transitions to [IdentityState.disabled] state.
  ZenResult<IdentityLifecycle> disable(String reason) {
    if (state == IdentityState.revoked) {
      return const ZenResult.err(ZenUnauthorizedError('Identity is revoked'));
    }
    return ZenResult.ok(IdentityLifecycle._(IdentityState.disabled, reason));
  }

  @override
  bool operator ==(Object other) =>
      other is IdentityLifecycle &&
      other.state == state &&
      other.reason == reason;
  @override
  int get hashCode => state.hashCode ^ (reason?.hashCode ?? 0);

  /// Internal: reconstructs from trusted state and reason.
  @internal
  const IdentityLifecycle.reconstruct(this.state, [this.reason]);
}

/// Domain value object representing external verification facts.
@immutable
final class IdentityVerificationFacts {
  /// Whether the email address has been verified.
  final bool emailVerified;

  /// Whether the phone number has been verified (optional).
  final bool phoneVerified;

  /// Creates [IdentityVerificationFacts].
  const IdentityVerificationFacts({
    required this.emailVerified,
    this.phoneVerified = false,
  });

  @override
  bool operator ==(Object other) =>
      other is IdentityVerificationFacts &&
      other.emailVerified == emailVerified &&
      other.phoneVerified == phoneVerified;
  @override
  int get hashCode => emailVerified.hashCode ^ phoneVerified.hashCode;
}

/// The central domain aggregate representing an identity.
final class Identity {
  /// The unique identifier for this identity.
  final IdentityId id;

  /// The current lifecycle state of the identity.
  final IdentityLifecycle lifecycle;

  /// The authority (roles and capabilities) granted to this identity.
  final Authority authority;

  /// Domain-level metadata.
  final ZenTimestamp createdAt;

  /// Creates an [Identity] aggregate.
  const Identity({
    required this.id,
    required this.lifecycle,
    required this.authority,
    required this.createdAt,
  });

  /// Factory for creating a new, pending identity.
  static Identity createPending({
    required IdentityId id,
    Authority authority = const Authority(),
  }) => Identity(
    id: id,
    lifecycle: IdentityLifecycle.initial(),
    authority: authority,
    createdAt: ZenTimestamp.now(),
  );

  /// Domain rule: Identity is activated if email is verified.
  static ZenResult<Identity> fromFacts({
    required IdentityId id,
    required Authority authority,
    required IdentityVerificationFacts facts,
    required ZenTimestamp createdAt,
  }) {
    var lifecycle = IdentityLifecycle.initial();
    if (facts.emailVerified) {
      final result = lifecycle.activate();
      lifecycle = result.fold((activated) => activated, (_) => lifecycle);
    }

    return ZenResult.ok(
      Identity(
        id: id,
        lifecycle: lifecycle,
        authority: authority,
        createdAt: createdAt,
      ),
    );
  }

  /// Evaluates if the identity is allowed to perform an action requiring a [Capability].
  ZenResult<bool> can(Capability capability) {
    if (!lifecycle.state.canAct) {
      return const ZenResult.err(
        ZenUnauthorizedError('Identity is not active'),
      );
    }
    return ZenResult.ok(authority.hasCapability(capability));
  }

  /// Transitions the identity to a new lifecycle state.
  Identity withLifecycle(IdentityLifecycle next) => Identity(
    id: id,
    lifecycle: next,
    authority: authority,
    createdAt: createdAt,
  );

  /// Updates the authority of the identity.
  Identity withAuthority(Authority next) => Identity(
    id: id,
    lifecycle: lifecycle,
    authority: next,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Identity &&
      other.id == id &&
      other.lifecycle == lifecycle &&
      other.authority == authority &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, lifecycle, authority, createdAt);
}

/// Interface for external identity providers (e.g. Auth0, Firebase Auth).
abstract class IdentityProvider {
  /// Retrieves external facts for a given [subject].
  Future<ZenResult<ExternalIdentity>> getIdentity(String subject);

  /// Resolves an [IdentityId] from an [ExternalIdentity].
  Future<ZenResult<IdentityId>> resolveId(ExternalIdentity external);
}

/// Represents an identity known to an external provider.
abstract class ExternalIdentity {
  /// The unique subject identifier in the external provider.
  String get subject;

  /// The raw claims or attributes from the external provider.
  Map<String, dynamic> get claims;
}

/// Domain hooks for identity lifecycle events.
abstract class IdentityHooks {
  /// Called when an identity is revoked.
  Future<ZenResult<void>> onRevoked(Identity identity, String reason);

  /// Called when an identity is disabled.
  Future<ZenResult<void>> onDisabled(Identity identity, String reason);
}
