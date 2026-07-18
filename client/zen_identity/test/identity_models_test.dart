import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:test/test.dart';

T ok<T>(ZenResult<T> result) => (result as ZenSuccess<T>).data;
Object err<T>(ZenResult<T> result) => (result as ZenFailure<T>).error;

void main() {
  group('IdentityId', () {
    test('create returns ok for valid value', () {
      final result = IdentityId.create('user_1');
      expect(result.isSuccess, isTrue);
      expect(ok<IdentityId>(result), isA<IdentityId>());
      expect(ok<IdentityId>(result).value, 'user_1');
    });
    test('create returns error for empty value', () {
      final result = IdentityId.create('');
      expect(result.isFailure, isTrue);
      expect(err<IdentityId>(result), isA<ZenValidationError>());
    });
    test('equality and hashCode', () {
      final a = ok<IdentityId>(IdentityId.create('foo'));
      final b = ok<IdentityId>(IdentityId.create('foo'));
      final c = ok<IdentityId>(IdentityId.create('bar'));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('Role', () {
    test('create returns ok for valid name', () {
      final result = Role.create('ADMIN');
      expect(result.isSuccess, isTrue);
      expect(ok<Role>(result), isA<Role>());
      expect(ok<Role>(result).name, 'ADMIN');
    });
    test('create returns error for invalid name', () {
      expect(Role.create('ab').isFailure, isTrue);
      expect(Role.create('admin').isFailure, isTrue);
      expect(Role.create('A!@#').isFailure, isTrue);
    });
    test('predefined roles', () {
      expect(Role.admin.name, 'ADMIN');
      expect(Role.user.name, 'USER');
    });
    test('equality and hashCode', () {
      final a = ok<Role>(Role.create('ADMIN'));
      final b = ok<Role>(Role.create('ADMIN'));
      final c = ok<Role>(Role.create('USER'));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('Capability', () {
    test('create returns ok for valid id', () {
      final result = Capability.create('edit_profile');
      expect(result.isSuccess, isTrue);
      expect(ok<Capability>(result), isA<Capability>());
      expect(ok<Capability>(result).id, 'edit_profile');
    });
    test('create returns error for invalid id', () {
      expect(Capability.create('AB').isFailure, isTrue);
      expect(Capability.create('edit-Profile').isFailure, isTrue);
    });
    test('equality and hashCode', () {
      final a = ok<Capability>(Capability.create('foo'));
      final b = ok<Capability>(Capability.create('foo'));
      final c = ok<Capability>(Capability.create('bar'));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('Authority', () {
    test('hasRole and hasCapability', () {
      final Role role = ok<Role>(Role.create('ADMIN'));
      final Capability cap = ok<Capability>(Capability.create('edit'));
      final auth = Authority(roles: {role}, capabilities: {cap});
      expect(auth.hasRole(role), isTrue);
      expect(auth.hasCapability(cap), isTrue);
      final Role userRole = ok<Role>(Role.create('USER'));
      final Capability viewCap = ok<Capability>(Capability.create('view'));
      expect(auth.hasRole(userRole), isFalse);
      expect(auth.hasCapability(viewCap), isFalse);
    });
    test('equality and hashCode', () {
      final Role r = ok<Role>(Role.create('ADMIN'));
      final Capability c = ok<Capability>(Capability.create('edit'));
      final a1 = Authority(roles: {r}, capabilities: {c});
      final a2 = Authority(roles: {r}, capabilities: {c});
      expect(a1, a2);
      expect(a1.hashCode, a2.hashCode);
    });
  });

  group('IdentityLifecycle', () {
    test('initial is pending', () {
      final l = IdentityLifecycle.initial();
      expect(l.state, IdentityState.pending);
      expect(l.reason, isNull);
    });
    test('activate transitions to active', () {
      final l = IdentityLifecycle.initial();
      final result = l.activate();
      expect(result.isSuccess, isTrue);
      expect(ok<IdentityLifecycle>(result).state, IdentityState.active);
    });
    test('revoke requires reason', () {
      final l = IdentityLifecycle.initial();
      final result = l.revoke('');
      expect(result.isFailure, isTrue);
      expect(err<IdentityLifecycle>(result), isA<ZenValidationError>());
    });
    test('disable transitions to disabled', () {
      final l = IdentityLifecycle.initial();
      final result = l.disable('reason');
      expect(result.isSuccess, isTrue);
      expect(ok<IdentityLifecycle>(result).state, IdentityState.disabled);
    });
    test('equality and hashCode', () {
      final l1 = IdentityLifecycle.initial();
      final l2 = IdentityLifecycle.initial();
      expect(l1, l2);
      expect(l1.hashCode, l2.hashCode);
    });
  });

  group('IdentityVerificationFacts', () {
    test('equality and hashCode', () {
      const a = IdentityVerificationFacts(emailVerified: true);
      const b = IdentityVerificationFacts(emailVerified: true);
      const c = IdentityVerificationFacts(emailVerified: false);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('Identity and Lifecycle behavior', () {
    test('revoke with reason transitions to revoked with reason', () {
      final l = IdentityLifecycle.initial();
      final res = l.revoke('policy violation');
      expect(res.isSuccess, isTrue);
      final r = ok<IdentityLifecycle>(res);
      expect(r.state, IdentityState.revoked);
      expect(r.reason, 'policy violation');
    });

    test('activate on revoked returns unauthorized', () {
      final l0 = IdentityLifecycle.initial();
      final l = ok<IdentityLifecycle>(l0.revoke('reason'));
      final res = l.activate();
      expect(res.isFailure, isTrue);
      expect(err<IdentityLifecycle>(res), isA<ZenUnauthorizedError>());
    });

    test('Identity.fromFacts activates when emailVerified true', () {
      final id = ok<IdentityId>(IdentityId.create('user_from_facts'));
      final cap = ok<Capability>(Capability.create('edit'));
      final authority = Authority(capabilities: {cap});
      final createdAt = ZenTimestamp.now();
      final res = Identity.fromFacts(
        id: id,
        authority: authority,
        facts: const IdentityVerificationFacts(emailVerified: true),
        createdAt: createdAt,
      );
      expect(res.isSuccess, isTrue);
      final identity = ok<Identity>(res);
      expect(identity.lifecycle.state, IdentityState.active);
    });

    test('Identity.fromFacts remains pending when emailVerified false', () {
      final id = ok<IdentityId>(IdentityId.create('user_from_facts_no'));
      const authority = Authority();
      final createdAt = ZenTimestamp.now();
      final res = Identity.fromFacts(
        id: id,
        authority: authority,
        facts: const IdentityVerificationFacts(emailVerified: false),
        createdAt: createdAt,
      );
      expect(res.isSuccess, isTrue);
      final identity = ok<Identity>(res);
      expect(identity.lifecycle.state, IdentityState.pending);
    });

    test('Identity.can returns unauthorized when not active', () {
      final id = ok<IdentityId>(IdentityId.create('pending_user'));
      final identity = Identity.createPending(id: id);
      final cap = ok<Capability>(Capability.create('edit'));
      final res = identity.can(cap);
      expect(res.isFailure, isTrue);
      expect(err<bool>(res), isA<ZenUnauthorizedError>());
    });

    test('Identity.can returns capability check when active', () {
      final id = ok<IdentityId>(IdentityId.create('active_user'));
      final cap = ok<Capability>(Capability.create('edit'));
      final authority = Authority(capabilities: {cap});
      final createdAt = ZenTimestamp.now();
      final identity = ok<Identity>(
        Identity.fromFacts(
          id: id,
          authority: authority,
          facts: const IdentityVerificationFacts(emailVerified: true),
          createdAt: createdAt,
        ),
      );
      final res = identity.can(cap);
      expect(res.isSuccess, isTrue);
      expect(ok<bool>(res), isTrue);

      final other = ok<Capability>(Capability.create('view'));
      final res2 = identity.can(other);
      expect(res2.isSuccess, isTrue);
      expect(ok<bool>(res2), isFalse);
    });

    test('withLifecycle and withAuthority produce distinct identities', () {
      final id = ok<IdentityId>(IdentityId.create('u4'));
      final identity = Identity.createPending(id: id);
      final newLifecycle = ok<IdentityLifecycle>(
        identity.lifecycle.disable('temp'),
      );
      final updated = identity.withLifecycle(newLifecycle);
      expect(updated.lifecycle.state, IdentityState.disabled);
      final newAuth = Authority(roles: {ok<Role>(Role.create('ADMIN'))});
      final updatedAuth = identity.withAuthority(newAuth);
      expect(updatedAuth.authority, newAuth);
      expect(identity == updatedAuth, isFalse);
    });

    test('disable on revoked returns unauthorized', () {
      final l0 = IdentityLifecycle.initial();
      final revoked = ok<IdentityLifecycle>(l0.revoke('bad'));
      final res = revoked.disable('temp');
      expect(res.isFailure, isTrue);
      expect(err<IdentityLifecycle>(res), isA<ZenUnauthorizedError>());
    });
  });
}
