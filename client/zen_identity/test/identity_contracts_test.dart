import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:test/test.dart';

void main() {
  group('AuthorityContract', () {
    test('fromDomain and toDomain round-trip', () {
      final domain = Authority(
        roles: {Role.admin, Role.user},
        capabilities: {
          const Capability.reconstruct('edit'),
          const Capability.reconstruct('view'),
        },
      );
      final contract = AuthorityContract.fromDomain(domain);
      final roundTrip = contract.toDomain();
      expect(roundTrip, domain);
    });
    test('fromJson and toJson round-trip', () {
      final json = {
        'roles': ['ADMIN', 'USER'],
        'capabilities': ['edit', 'view'],
      };
      final contract = AuthorityContract.fromJson(json);
      expect(contract.toJson(), json);
    });
  });

  group('IdentityLifecycleContract', () {
    test('fromDomain and toDomain round-trip', () {
      const domain = IdentityLifecycle.reconstruct(
        IdentityState.revoked,
        'reason',
      );
      final contract = IdentityLifecycleContract.fromDomain(domain);
      final roundTrip = contract.toDomain();
      expect(roundTrip, domain);
    });
    test('fromJson and toJson round-trip', () {
      final json = {'state': 'revoked', 'reason': 'foo'};
      final contract = IdentityLifecycleContract.fromJson(json);
      expect(contract.toJson(), json);
    });
  });

  group('IdentityContract', () {
    test('fromDomain and toDomain round-trip', () {
      final domain = Identity(
        id: const IdentityId.reconstruct('id1'),
        lifecycle: const IdentityLifecycle.reconstruct(IdentityState.active),
        authority: Authority(roles: {Role.admin}),
        createdAt: ZenTimestamp.fromMilliseconds(123456),
      );
      final contract = IdentityContract.fromDomain(domain);
      final roundTrip = contract.toDomain();
      expect(roundTrip, domain);
    });
    test('fromJson and toJson round-trip', () {
      final json = <String, dynamic>{
        'id': 'id1',
        'lifecycle': {'state': 'active'},
        'authority': {
          'roles': <String>['ADMIN'],
          'capabilities': <String>[],
        },
        'createdAt': 123456,
      };
      final contract = IdentityContract.fromJson(json);
      expect(contract.toJson(), json);
    });
  });

  group('AuthorityContract edge cases', () {
    test('handles missing roles/capabilities', () {
      final contract = AuthorityContract.fromJson(const {});
      expect(contract.roles, isEmpty);
      expect(contract.capabilities, isEmpty);
    });

    test('handles null roles/capabilities', () {
      final contract = AuthorityContract.fromJson(const {
        'roles': null,
        'capabilities': null,
      });
      expect(contract.roles, isEmpty);
      expect(contract.capabilities, isEmpty);
    });

    test('toDomain with invalid role/capability', () {
      const contract = AuthorityContract(
        roles: ['INVALID!'],
        capabilities: ['invalid-cap'],
      );
      final authority = contract.toDomain();
      // reconstruct should preserve values even if they would be invalid
      expect(authority.roles.first.name, 'INVALID!');
      expect(authority.capabilities.first.id, 'invalid-cap');
    });
  });
}
