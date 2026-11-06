@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zen_demo_client/src/backend_network_io.dart';
import 'package:zen_transport/src/http/session_client_io.dart';

void main() {
  final throwsSocketException = throwsA(isA<SocketException>());
  test('refuses local, multicast, unspecified and translated destinations', () {
    for (final value in [
      '0.0.0.0',
      '10.0.0.1',
      '100.64.0.1',
      '169.254.1.1',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.1.1',
      '192.0.0.1',
      '192.0.2.1',
      '198.18.0.1',
      '198.51.100.1',
      '203.0.113.1',
      '224.0.0.251',
      '255.255.255.255',
      '::',
      'fc00::1',
      'fd12::1',
      'fe80::1',
      'ff02::fb',
      '::ffff:192.168.1.1',
      '64:ff9b::c0a8:101',
      '2001:db8::1',
      '2002:c0a8:101::1',
      '3fff::1',
    ]) {
      expect(BackendNetwork.isBackendAddress(InternetAddress(value)), isFalse, reason: value);
    }
    for (final value in [
      '127.0.0.1',
      '127.1.2.3',
      '::1',
      '::ffff:127.0.0.1',
      '8.8.8.8',
      '2606:4700:4700::1111',
      '2001:4860:4860::8888',
    ]) {
      expect(BackendNetwork.isBackendAddress(InternetAddress(value)), isTrue, reason: value);
    }
  });

  test('rejects discovery names and LAN literals before resolution', () {
    for (final host in [
      'printer',
      'printer.local',
      'printer.LOCAL.',
      'router.home.arpa',
      '10.0.0.1',
      '192.168.1.1',
      '[fe80::1%25en0]',
      '[ff02::fb]',
    ]) {
      expect(() => BackendNetwork(Uri.parse('http://$host')), throwsSocketException, reason: host);
    }
  });

  test('rejects unexpected origins and DNS rebinding before opening a socket', () async {
    var lookups = 0;
    final policy = BackendNetwork(
      Uri.parse('https://backend.example'),
      lookup: (host) async {
        expect(host, 'backend.example.', reason: 'DNS must not append local search domains');
        lookups++;
        return [InternetAddress('8.8.8.8'), InternetAddress.loopbackIPv4];
      },
    );
    // Loopback is allowed only when explicitly configured, never as a public
    // hostname's DNS answer. No test attempts a connection to another device.
    for (final url in [
      'http://backend.example',
      'https://backend.example:444',
      'https://other.example',
      'https://user@backend.example',
    ]) {
      await expectLater(policy.connect(Uri.parse(url), null, null), throwsSocketException);
    }
    expect(lookups, 0);
    await expectLater(policy.connect(policy.backend, '127.0.0.1', 8080), throwsSocketException);
    await expectLater(policy.connect(policy.backend, null, null), throwsSocketException);
    expect(lookups, 1);
  });

  test('rejects a public name resolving to private or multicast addresses', () async {
    for (final address in ['192.168.1.1', '224.0.0.251', 'fe80::1', '::ffff:10.0.0.1']) {
      final policy = BackendNetwork(
        Uri.parse('https://backend.example'),
        lookup: (_) async => [InternetAddress(address)],
      );
      await expectLater(policy.connect(policy.backend, null, null), throwsSocketException);
    }
  });

  test('real HTTP, cookies and WebSocket work; redirects cannot reach another listener', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    addTearDown(() => other.close(force: true));
    var unexpectedRequests = 0;
    other.listen((request) {
      unexpectedRequests++;
      request.response.close();
    });
    server.listen((request) async {
      if (request.uri.path == '/ws') {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen(socket.add);
      } else if (request.uri.path == '/redirect') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, 'http://127.0.0.1:${other.port}/');
        await request.response.close();
      } else {
        request.response.cookies.add(Cookie('zen_access_token', 'test-session'));
        request.response.write(request.cookies.map((c) => c.value).join());
        await request.response.close();
      }
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    await HttpOverrides.runWithHttpOverrides(() async {
      final session = CookieJarClient();
      addTearDown(session.close);
      expect((await session.get(base)).statusCode, 200);
      expect((await session.get(base)).body, 'test-session');
      await expectLater(session.get(base.resolve('/redirect')), throwsSocketException);
      final socket = await WebSocket.connect('ws://127.0.0.1:${server.port}/ws');
      socket.add('echo');
      expect(await socket.first, 'echo');
      await socket.close();
      expect(unexpectedRequests, 0);
    }, BackendNetwork(base));
  });

  test('HTTPS and WSS preserve encryption, trust and hostname verification', () async {
    final tls = SecurityContext()
      ..useCertificateChain('test/fixtures/tls/localhost.crt')
      ..usePrivateKey('test/fixtures/tls/localhost.key');
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, tls);
    addTearDown(() => server.close(force: true));
    server.listen(
      (request) async {
        if (request.uri.path == '/ws') {
          final socket = await WebSocketTransformer.upgrade(request);
          socket.listen(socket.add);
        } else {
          request.response.write('encrypted');
          await request.response.close();
        }
      },
      onError: (Object error) {
        // Clients below deliberately reject this test-only certificate.
        expect(error, isA<TlsException>());
      },
    );
    final base = Uri.parse('https://localhost:${server.port}');
    final policy = BackendNetwork(base);
    final untrusted = policy.createHttpClient(null);
    addTearDown(() => untrusted.close(force: true));
    await expectLater(untrusted.getUrl(base), throwsA(isA<HandshakeException>()));

    final trust = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/fixtures/tls/ca.crt');
    final client = policy.createHttpClient(trust);
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(base)).close();
    expect(response.statusCode, 200);
    await response.drain<void>();
    final socket = await WebSocket.connect(
      'wss://localhost:${server.port}/ws',
      customClient: client,
    );
    socket.add('encrypted echo');
    expect(await socket.first, 'encrypted echo');
    await socket.close();

    final wrongName = Uri.parse('https://127.0.0.1:${server.port}');
    final wrongClient = BackendNetwork(wrongName).createHttpClient(trust);
    addTearDown(() => wrongClient.close(force: true));
    await expectLater(wrongClient.getUrl(wrongName), throwsA(isA<HandshakeException>()));
  });
}
