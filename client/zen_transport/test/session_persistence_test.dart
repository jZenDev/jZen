@TestOn('vm')
library;

// Proves the session survives a process, which is the whole point of persisting anything: a
// browser keeps session cookies for their Max-Age, nothing did that on native, so before this a
// user signed in again on every launch.
//
// No mock of the persistence itself - a live dart:io HttpServer issues real Set-Cookie headers
// and a second client, standing in for the next launch, restores from the same store. The store
// is a fake rather than the keystore one on purpose: SecureTokenStore lives in zen_secure_store
// because it imports dart:ui, which this VM suite cannot compile at all. That separation is the
// design (see TokenStore), and this file is where it earns its keep.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zen_transport/src/http/session_client_io.dart';
import 'package:zen_transport/src/http/token_store.dart';

/// Records what was written, so a test can assert on the token at rest, not only on behaviour.
class RecordingTokenStore implements TokenStore {
  String? value;
  int writes = 0;
  int deletes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async {
    value = token;
    writes++;
  }

  @override
  Future<void> delete() async {
    value = null;
    deletes++;
  }
}

/// Stands in for a Keychain that is locked, unreachable, or missing its entitlement.
class _ThrowingTokenStore implements TokenStore {
  @override
  Future<String?> read() async => throw const _KeystoreUnavailable();

  @override
  Future<void> write(String token) async => throw const _KeystoreUnavailable();

  @override
  Future<void> delete() async => throw const _KeystoreUnavailable();
}

class _KeystoreUnavailable implements Exception {
  const _KeystoreUnavailable();
}

void main() {
  late HttpServer server;
  late Uri baseUri;
  // What /refresh will mint next, so a test can prove rotation reached the store.
  String nextRefresh = 'refresh-1';

  setUp(() async {
    nextRefresh = 'refresh-1';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
    server.listen((request) async {
      switch (request.uri.path) {
        case '/login':
          // Both cookies, exactly as SessionService issues them: an hour and seven days.
          request.response.cookies.add(
            Cookie('zen_access_token', 'access-1')
              ..httpOnly = true
              ..maxAge = 3600,
          );
          request.response.cookies.add(
            Cookie('zen_refresh_token', nextRefresh)
              ..httpOnly = true
              ..maxAge = 604800,
          );
          request.response
            ..statusCode = HttpStatus.ok
            ..write('ok');
        case '/refresh':
          // Reads the refresh cookie and rotates it, like POST /api/v1/auth/refresh.
          final sent = request.cookies
              .where((c) => c.name == 'zen_refresh_token')
              .map((c) => c.value)
              .join();
          if (sent.isEmpty) {
            request.response
              ..statusCode = HttpStatus.unauthorized
              ..write('no refresh cookie');
          } else {
            nextRefresh = 'refresh-2';
            request.response.cookies.add(
              Cookie('zen_refresh_token', nextRefresh)
                ..httpOnly = true
                ..maxAge = 604800,
            );
            request.response
              ..statusCode = HttpStatus.ok
              ..write(jsonEncode({'refreshed': sent}));
          }
        case '/logout':
          for (final name in ['zen_access_token', 'zen_refresh_token']) {
            request.response.cookies.add(
              Cookie(name, '')
                ..httpOnly = true
                ..maxAge = 0,
            );
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..write('bye');
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  test('login persists the refresh token and not the access token', () async {
    final store = RecordingTokenStore();
    final client = CookieJarClient(store: store);
    addTearDown(client.close);

    await client.get(baseUri.resolve('/login'));

    expect(store.value, isNotNull, reason: 'the refresh token must be persisted');
    expect(store.value, contains('refresh-1'));
    // The access token is short-lived and re-obtainable; keeping it at rest buys one round trip
    // and widens the blast radius of a compromised device. It must not be written down.
    expect(store.value, isNot(contains('access-1')));
  });

  test('a second client restores the session and refreshes it', () async {
    final store = RecordingTokenStore();
    final first = CookieJarClient(store: store);
    await first.get(baseUri.resolve('/login'));
    first.close();

    // A new process: nothing in memory, everything from the store.
    final next = CookieJarClient(store: store);
    addTearDown(next.close);
    expect(await next.restore(), isTrue);

    final resp = await next.get(baseUri.resolve('/refresh'));
    expect(resp.statusCode, 200);
    expect(
      jsonDecode(resp.body)['refreshed'],
      'refresh-1',
      reason: 'the restored cookie must actually reach the server',
    );
  });

  test('a rotated refresh token replaces the stored one', () async {
    final store = RecordingTokenStore();
    final client = CookieJarClient(store: store);
    addTearDown(client.close);

    await client.get(baseUri.resolve('/login'));
    await client.get(baseUri.resolve('/refresh'));

    // Rotation is what makes a token lifted from an old backup go stale (RFC 9700). If the store
    // kept the first token, the next launch would present a dead one and sign the user out.
    expect(store.value, contains('refresh-2'));
    expect(store.value, isNot(contains('refresh-1')));
  });

  test('restore reports false when nothing was ever stored', () async {
    final client = CookieJarClient(store: RecordingTokenStore());
    addTearDown(client.close);

    expect(await client.restore(), isFalse);
    expect(client.cookies, isEmpty);
  });

  test('an expired stored token is discarded, not sent', () async {
    final store = RecordingTokenStore()
      ..value = jsonEncode({
        'value': 'long-dead',
        'expires': DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String(),
      });
    final client = CookieJarClient(store: store);
    addTearDown(client.close);

    expect(await client.restore(), isFalse);
    expect(client.cookies, isEmpty);
    // Dropped rather than left behind: it cannot succeed, so keeping it only leaves a credential
    // lying around.
    expect(store.value, isNull);
    expect(store.deletes, 1);
  });

  test('a corrupt stored entry is dropped rather than wedging every launch', () async {
    final store = RecordingTokenStore()..value = 'not json at all';
    final client = CookieJarClient(store: store);
    addTearDown(client.close);

    expect(await client.restore(), isFalse);
    expect(store.value, isNull);
  });

  test('logout clears the persisted token as well as the jar', () async {
    final store = RecordingTokenStore();
    final client = CookieJarClient(store: store);
    addTearDown(client.close);

    await client.get(baseUri.resolve('/login'));
    expect(store.value, isNotNull);

    await client.get(baseUri.resolve('/logout'));

    expect(client.cookies, isEmpty);
    // The server's Max-Age=0 must reach the persistent store too, or the next launch would
    // restore a session the user just ended.
    expect(store.value, isNull);
  });

  test('clear() ends the session without the server', () async {
    final store = RecordingTokenStore();
    final client = CookieJarClient(store: store);
    addTearDown(client.close);

    await client.get(baseUri.resolve('/login'));
    await client.clear();

    expect(client.cookies, isEmpty);
    expect(store.value, isNull);
  });

  test('a keystore that refuses to read does not take the launch down', () async {
    final client = CookieJarClient(store: _ThrowingTokenStore());
    addTearDown(client.close);

    // A locked or unreachable Keychain is a platform condition, not a bug in the app. The honest
    // answer is "no session to resume" — a crash on launch would be a far worse trade.
    expect(await client.restore(), isFalse);
  });

  test('a keystore that refuses to write does not fail the request', () async {
    final client = CookieJarClient(store: _ThrowingTokenStore());
    addTearDown(client.close);

    final resp = await client.get(baseUri.resolve('/login'));

    // The login itself succeeded and the jar holds the cookies; only the durability is lost.
    expect(resp.statusCode, 200);
    expect(client.cookies.map((c) => c.name), contains('zen_access_token'));
  });

  test('without a store the session ends with the process, as before', () async {
    final client = CookieJarClient();
    addTearDown(client.close);

    await client.get(baseUri.resolve('/login'));

    // The default is InMemoryTokenStore: a fresh client shares nothing with this one.
    final next = CookieJarClient();
    addTearDown(next.close);
    expect(await next.restore(), isFalse);
  });
}
