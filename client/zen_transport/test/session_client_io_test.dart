@TestOn('vm')
library;

// Proves the native session gap (ROADMAP step 4) is closed for real: no mock, a live dart:io
// HttpServer sets a cookie on one response and the CookieJarClient resends it on the next
// request - the exact login -> authenticated-call behaviour SupabaseIdentityRepository depends
// on off-web. Also covers logout: a Max-Age=0 cookie evicts the entry from the jar.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:zen_transport/src/http/session_client_io.dart';

void main() {
  late HttpServer server;
  late Uri baseUri;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
    server.listen((request) async {
      switch (request.uri.path) {
        case '/login':
          // Set an httpOnly session cookie plus the JS-readable CSRF token, like the Quarkus
          // AuthResource does - it issues both together, always.
          request.response.cookies.add(Cookie('zen_access_token', 'access-jwt')..httpOnly = true);
          request.response.cookies.add(Cookie('XSRF-TOKEN', 'csrf-token')..httpOnly = false);
          request.response
            ..statusCode = HttpStatus.ok
            ..write('ok');
        case '/echo-csrf':
          // Report what the client sent back in the double-submit header, and on which method.
          request.response
            ..statusCode = HttpStatus.ok
            ..write(jsonEncode({
              'header': request.headers.value('X-CSRF-Token') ?? '',
              'method': request.method,
            }));
        case '/whoami':
          // Echo back whatever session cookie the client resent.
          final sid = request.cookies
              .where((c) => c.name == 'zen_access_token')
              .map((c) => c.value)
              .join();
          request.response
            ..statusCode = HttpStatus.ok
            ..write(jsonEncode({'token': sid}));
        case '/logout':
          // Clear the cookies the way SessionService.clearCookie does (Max-Age=0). AuthResource
          // clears the CSRF token alongside the session, so the fixture does too.
          request.response.cookies.add(Cookie('zen_access_token', '')..maxAge = 0);
          request.response.cookies.add(Cookie('XSRF-TOKEN', '')..maxAge = 0);
          request.response.statusCode = HttpStatus.noContent;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('resends the session cookie set on a prior response', () async {
    final client = CookieJarClient();
    addTearDown(client.close);

    final login = await client.get(baseUri.resolve('/login'));
    expect(login.statusCode, 200);
    expect(client.cookies.map((c) => c.name), contains('zen_access_token'));

    final who = await client.get(baseUri.resolve('/whoami'));
    expect(who.statusCode, 200);
    expect(
      jsonDecode(who.body)['token'],
      'access-jwt',
      reason: 'the jar must resend the cookie captured at /login',
    );
  });

  test('a fresh client without the cookie sends nothing', () async {
    final client = CookieJarClient();
    addTearDown(client.close);

    final who = await client.get(baseUri.resolve('/whoami'));
    expect(jsonDecode(who.body)['token'], '');
  });

  test('a Max-Age=0 cookie evicts the session on logout', () async {
    final client = CookieJarClient();
    addTearDown(client.close);

    await client.get(baseUri.resolve('/login'));
    expect(client.cookies.map((c) => c.name), contains('zen_access_token'));

    final logout = await client.get(baseUri.resolve('/logout'));
    expect(logout.statusCode, 204);
    expect(client.cookies, isEmpty, reason: 'logout must clear the jar');

    final who = await client.get(baseUri.resolve('/whoami'));
    expect(jsonDecode(who.body)['token'], '');
  });

  group('the double-submit CSRF echo', () {
    test('a mutating request echoes the XSRF-TOKEN cookie as X-CSRF-Token', () async {
      final client = CookieJarClient();
      addTearDown(client.close);

      await client.get(baseUri.resolve('/login'));
      final echoed = await client.post(baseUri.resolve('/echo-csrf'));

      expect(
        jsonDecode(echoed.body)['header'],
        'csrf-token',
        reason: 'without this the server refuses every mutating call the native app makes',
      );
    });

    test('a GET echoes nothing', () async {
      final client = CookieJarClient();
      addTearDown(client.close);

      await client.get(baseUri.resolve('/login'));
      final echoed = await client.get(baseUri.resolve('/echo-csrf'));

      expect(jsonDecode(echoed.body)['header'], '', reason: 'a read carries no CSRF risk');
    });

    test('a client with no session echoes nothing', () async {
      final client = CookieJarClient();
      addTearDown(client.close);

      final echoed = await client.post(baseUri.resolve('/echo-csrf'));

      // Nothing to echo and nothing to protect: an anonymous request has no ambient credential
      // for a forged call to ride on, and the server does not enforce against one.
      expect(jsonDecode(echoed.body)['header'], '');
    });

    test("an explicit per-call header is not overwritten", () async {
      final client = CookieJarClient();
      addTearDown(client.close);

      await client.get(baseUri.resolve('/login'));
      final echoed = await client.post(
        baseUri.resolve('/echo-csrf'),
        headers: {'X-CSRF-Token': 'caller-supplied'},
      );

      expect(jsonDecode(echoed.body)['header'], 'caller-supplied');
    });
  });

  test('createSessionClient returns a working cookie-jar client on native', () async {
    final client = createPlatformSessionClient();
    addTearDown(client.close);
    expect(client, isA<http.BaseClient>());

    await client.get(baseUri.resolve('/login'));
    final who = await client.get(baseUri.resolve('/whoami'));
    expect(jsonDecode(who.body)['token'], 'access-jwt');
  });
}
