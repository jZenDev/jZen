import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_transport/zen_transport.dart' as pb;

/// Drives [SupabaseIdentityRepository] through a real [pb.ZenClient] whose HTTP layer is a
/// [MockClient], so the repository, the transport codec, and the proto <-> contract mapping
/// are all exercised without a live backend. The client is pinned to JSON so responses are
/// easy to craft as canonical proto3 JSON.
void main() {
  SupabaseIdentityRepository repoReturning(
    http.Response Function(http.Request request) handler,
  ) {
    final client = pb.ZenClient(
      baseUrl: 'http://test.local',
      format: pb.ZenTransportFormat.json,
      httpClient: MockClient((request) async => handler(request)),
    );
    return SupabaseIdentityRepository(client: client);
  }

  http.Response jsonResponse(Object? proto3Json, {int status = 200}) => http.Response(
    jsonEncode(proto3Json),
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'x-zen-transport': 'json',
    },
  );

  Map<String, dynamic> identityJson({
    required String id,
    List<String> roles = const ['user'],
  }) =>
      pb.Identity(id: id, lifecycleState: 'active', roles: roles).toProto3Json()
          as Map<String, dynamic>;

  group('loginWithEmail', () {
    test('maps a 200 Identity to an IdentityContract', () async {
      final repo = repoReturning(
        (req) {
          expect(req.url.path, '/api/v1/auth/login');
          expect(req.method, 'POST');
          return jsonResponse(identityJson(id: 'u1', roles: ['user', 'admin']));
        },
      );

      final result = await repo.loginWithEmail(email: 'a@b.com', password: 'secret1');

      expect(result.isSuccess, isTrue);
      final contract = result.dataOrNull!;
      expect(contract.id, 'u1');
      expect(contract.authority.roles, ['user', 'admin']);
      expect(contract.lifecycle.state, 'active');
    });

    test('rejects an invalid email before any network call', () async {
      var called = false;
      final repo = repoReturning((req) {
        called = true;
        return jsonResponse(identityJson(id: 'x'));
      });

      final result = await repo.loginWithEmail(email: 'not-an-email', password: 'secret1');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<ZenValidationError>());
      expect(called, isFalse, reason: 'must short-circuit before hitting the network');
    });

    test('surfaces a ZenError from a 401', () async {
      final repo = repoReturning(
        (req) => jsonResponse(
          pb.ZenError(code: 'unauthorized', message: 'Invalid credentials.').toProto3Json(),
          status: 401,
        ),
      );

      final result = await repo.loginWithEmail(email: 'a@b.com', password: 'wrong1');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isNotNull);
    });
  });

  group('registerWithEmail', () {
    test('posts to /register and maps the Identity', () async {
      final repo = repoReturning((req) {
        expect(req.url.path, '/api/v1/auth/register');
        return jsonResponse(identityJson(id: 'u2'));
      });

      final result = await repo.registerWithEmail(email: 'new@b.com', password: 'secret1');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.id, 'u2');
    });

    /// The server seeds users.language from this header at registration, and every later
    /// localized email for that user follows from the column. The repository takes no locale
    /// argument: it rides along as ambient client context, so the app cannot forget it.
    test('carries the app locale as Accept-Language', () async {
      String? seen;
      final client = pb.ZenClient(
        baseUrl: 'http://test.local',
        format: pb.ZenTransportFormat.json,
        httpClient: MockClient((request) async {
          seen = request.headers[pb.acceptLanguageHeaderName];
          return jsonResponse(identityJson(id: 'u3'));
        }),
        language: () => 'uk',
      );

      final result = await SupabaseIdentityRepository(
        client: client,
      ).registerWithEmail(email: 'uk@b.com', password: 'secret1');

      expect(result.isSuccess, isTrue);
      expect(seen, 'uk');
    });
  });

  group('getCurrentIdentity', () {
    test('returns ok(null) on a 204 (anonymous) probe', () async {
      final repo = repoReturning(
        (req) => http.Response('', 204, headers: {'x-zen-transport': 'json'}),
      );

      final result = await repo.getCurrentIdentity();

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, isNull);
    });

    test('returns the contract when a session exists', () async {
      final repo = repoReturning((req) => jsonResponse(identityJson(id: 'me')));

      final result = await repo.getCurrentIdentity();

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.id, 'me');
    });
  });

  group('restorePassword', () {
    test('returns ok on a 204', () async {
      final repo = repoReturning(
        (req) => http.Response('', 204, headers: {'x-zen-transport': 'json'}),
      );
      final result = await repo.restorePassword(email: 'a@b.com');
      expect(result.isSuccess, isTrue);
    });

    test('rejects an invalid email', () async {
      final repo = repoReturning((req) => jsonResponse(identityJson(id: 'x')));
      final result = await repo.restorePassword(email: 'nope');
      expect(result.errorOrNull, isA<ZenValidationError>());
    });
  });

  group('logout', () {
    test('returns ok on a 204', () async {
      final repo = repoReturning(
        (req) {
          expect(req.url.path, '/api/v1/auth/logout');
          return http.Response('', 204, headers: {'x-zen-transport': 'json'});
        },
      );
      final result = await repo.logout();
      expect(result.isSuccess, isTrue);
    });
  });
}
