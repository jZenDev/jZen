// Exercises the typed send<T> API and the client's two invariants (default codec via
// selectDefaultCodec; a decode failure surfaces a ZenError, never a silent null).
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:zen_transport/zen_transport.dart';

/// Builds a response carrying [message] encoded in [format], echoing the X-Zen-Transport
/// header the way the Quarkus server does.
http.Response _encodedResponse(dynamic message, ZenTransportFormat format, int status) {
  final bytes = ZenProtoCodec.encode(message, format);
  // The http package lowercases response header keys; emulate that here.
  return http.Response.bytes(
    bytes,
    status,
    headers: {
      zenTransportHeaderName.toLowerCase(): format.value,
      'content-type': format == ZenTransportFormat.json
          ? 'application/json'
          : 'application/x-protobuf',
    },
  );
}

void main() {
  group('ZenClient construction', () {
    test('default format comes from selectDefaultCodec()', () {
      final client = ZenClient(baseUrl: 'http://localhost:8080');
      expect(client.format, selectDefaultCodec());
    });

    test('explicit format overrides the default', () {
      final client = ZenClient(baseUrl: 'http://localhost:8080', format: ZenTransportFormat.json);
      expect(client.format, ZenTransportFormat.json);
    });
  });

  group('ZenClient happy paths', () {
    for (final format in ZenTransportFormat.values) {
      test('GET decodes a ${format.value} response into a typed message', () async {
        final mock = MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.toString(), 'http://host/api/v1/health');
          expect(request.headers[zenTransportHeaderName], format.value);
          expect(request.headers[requestIdHeaderName], matches(r'^req-\d+-\d+$'));
          return _encodedResponse(
            HealthStatus(status: 'ok', service: 'zen-demo-server'),
            format,
            200,
          );
        });
        final client = ZenClient(baseUrl: 'http://host', format: format, httpClient: mock);

        final result = await client.get(HealthStatus.new, '/api/v1/health');
        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull?.status, 'ok');
        expect(result.dataOrNull?.service, 'zen-demo-server');
      });
    }

    test('POST encodes a typed body and sends it', () async {
      late Uint8List sentBytes;
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        sentBytes = request.bodyBytes;
        return _encodedResponse(
          HealthStatus(status: 'ok', service: 'zen-demo-server'),
          ZenTransportFormat.protobuf,
          200,
        );
      });
      final client = ZenClient(
        baseUrl: 'http://host',
        format: ZenTransportFormat.protobuf,
        httpClient: mock,
      );

      final body = PageRequest(page: 1, size: 20);
      final result = await client.post(HealthStatus.new, '/api/v1/things', body: body);

      expect(result.isSuccess, isTrue);
      // The server-side would decode sentBytes back to the original PageRequest.
      final roundTripped = ZenProtoCodec.decode(
        sentBytes,
        ZenTransportFormat.protobuf,
        PageRequest.new,
      );
      expect(roundTripped, body);
    });

    test('response format is re-negotiated from the response header', () async {
      // Client speaks protobuf, but the server answers in json (and says so).
      final mock = MockClient((request) async {
        return _encodedResponse(
          HealthStatus(status: 'ok', service: 'zen-demo-server'),
          ZenTransportFormat.json,
          200,
        );
      });
      final client = ZenClient(
        baseUrl: 'http://host',
        format: ZenTransportFormat.protobuf,
        httpClient: mock,
      );

      final result = await client.get(HealthStatus.new, '/api/v1/health');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.service, 'zen-demo-server');
    });

    test('empty 204 body yields an empty message', () async {
      final mock = MockClient((request) async => http.Response('', 204));
      final client = ZenClient(baseUrl: 'http://host', httpClient: mock);

      final result = await client.delete(HealthStatus.new, '/api/v1/things/1');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.status, '');
    });

    test('custom headers are passed through and can override defaults', () async {
      final mock = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer token');
        expect(request.headers['x-custom'], 'yes');
        return _encodedResponse(
          HealthStatus(status: 'ok', service: 'zen-demo-server'),
          ZenTransportFormat.json,
          200,
        );
      });
      final client = ZenClient(
        baseUrl: 'http://host',
        format: ZenTransportFormat.json,
        httpClient: mock,
      );

      final result = await client.get(
        HealthStatus.new,
        '/api/v1/health',
        headers: {'Authorization': 'Bearer token', 'X-Custom': 'yes'},
      );
      expect(result.isSuccess, isTrue);
    });
  });

  group('ZenClient Accept-Language', () {
    /// Builds a client whose [language] callback returns whatever [locale] currently holds,
    /// and captures the headers the request went out with.
    ZenClient clientReading(String Function() locale, void Function(http.Request) capture) {
      final mock = MockClient((request) async {
        capture(request);
        return _encodedResponse(
          HealthStatus(status: 'ok', service: 'zen-demo-server'),
          ZenTransportFormat.json,
          200,
        );
      });
      return ZenClient(
        baseUrl: 'http://host',
        format: ZenTransportFormat.json,
        httpClient: mock,
        language: locale,
      );
    }

    test('the supplied locale rides on every request', () async {
      http.Request? seen;
      final client = clientReading(() => 'uk', (r) => seen = r);

      await client.get(HealthStatus.new, '/api/v1/health');

      expect(seen!.headers[acceptLanguageHeaderName], 'uk');
    });

    test('the header is omitted when no locale is supplied', () async {
      http.Request? seen;
      final mock = MockClient((request) async {
        seen = request;
        return _encodedResponse(
          HealthStatus(status: 'ok', service: 'zen-demo-server'),
          ZenTransportFormat.json,
          200,
        );
      });
      final client = ZenClient(
        baseUrl: 'http://host',
        format: ZenTransportFormat.json,
        httpClient: mock,
      );

      await client.get(HealthStatus.new, '/api/v1/health');

      expect(seen!.headers.containsKey(acceptLanguageHeaderName), isFalse);
    });

    test('the locale is re-read per request, so a mid-session switch applies', () async {
      var current = 'en';
      final seen = <String?>[];
      final client = clientReading(
        () => current,
        (r) => seen.add(r.headers[acceptLanguageHeaderName]),
      );

      await client.get(HealthStatus.new, '/api/v1/health');
      current = 'uk';
      await client.get(HealthStatus.new, '/api/v1/health');

      expect(seen, ['en', 'uk']);
    });

    test('an explicit per-call header wins over the ambient locale', () async {
      http.Request? seen;
      final client = clientReading(() => 'en', (r) => seen = r);

      await client.get(
        HealthStatus.new,
        '/api/v1/health',
        headers: {acceptLanguageHeaderName: 'uk'},
      );

      expect(seen!.headers[acceptLanguageHeaderName], 'uk');
    });
  });

  group('ZenClient error handling', () {
    test('non-2xx decodes the body into a ZenError (common.proto)', () async {
      final mock = MockClient((request) async {
        return _encodedResponse(
          ZenError(code: 'not_found', message: 'No such thing'),
          ZenTransportFormat.json,
          404,
        );
      });
      final client = ZenClient(
        baseUrl: 'http://host',
        format: ZenTransportFormat.json,
        httpClient: mock,
      );

      final result = await client.get(HealthStatus.new, '/api/v1/things/1');
      expect(result.isFailure, isTrue);
      final error = result.errorOrNull;
      expect(error, isA<ZenTransportError>());
      expect((error as ZenTransportError).zenError.code, 'not_found');
      expect(error.zenError.message, 'No such thing');
      expect(error.message, 'No such thing');
    });

    test('non-2xx with empty body synthesizes a ZenError from the status', () async {
      final mock = MockClient((request) async => http.Response('', 403, reasonPhrase: 'Forbidden'));
      final client = ZenClient(baseUrl: 'http://host', httpClient: mock);

      final result = await client.get(HealthStatus.new, '/api/v1/secret');
      expect(result.isFailure, isTrue);
      final error = result.errorOrNull! as ZenTransportError;
      expect(error.zenError.code, ZenTransportErrorCode.http.wire);
      expect(error.zenError.message, 'Forbidden');
    });

    test('malformed 200 body surfaces a ZenError, not a null/ok', () async {
      final mock = MockClient((request) async {
        return http.Response.bytes(
          Uint8List.fromList([0x7b, 0x7b, 0x7b]), // "{{{" - not valid JSON
          200,
          headers: {zenTransportHeaderName.toLowerCase(): 'json'},
        );
      });
      final client = ZenClient(
        baseUrl: 'http://host',
        format: ZenTransportFormat.json,
        httpClient: mock,
      );

      final result = await client.get(HealthStatus.new, '/api/v1/health');
      expect(result.isFailure, isTrue);
      final error = result.errorOrNull! as ZenTransportError;
      expect(error.zenError.code, ZenTransportErrorCode.decode.wire);
    });

    test('unrecognized X-Zen-Transport response header is a ZenError', () async {
      final mock = MockClient((request) async {
        return http.Response.bytes(
          Uint8List.fromList([1, 2, 3]),
          200,
          headers: {zenTransportHeaderName.toLowerCase(): 'bson'},
        );
      });
      final client = ZenClient(baseUrl: 'http://host', httpClient: mock);

      final result = await client.get(HealthStatus.new, '/api/v1/health');
      expect(result.isFailure, isTrue);
      final error = result.errorOrNull! as ZenTransportError;
      expect(error.zenError.code, ZenTransportErrorCode.decode.wire);
    });

    test('network failure surfaces a ZenError, not a throw', () async {
      final mock = MockClient((request) async {
        throw http.ClientException('connection refused');
      });
      final client = ZenClient(baseUrl: 'http://host', httpClient: mock);

      final result = await client.get(HealthStatus.new, '/api/v1/health');
      expect(result.isFailure, isTrue);
      final error = result.errorOrNull! as ZenTransportError;
      expect(error.zenError.code, ZenTransportErrorCode.network.wire);
    });
  });

  group('ZenClient request ids', () {
    test('request ids are unique and monotonic', () async {
      final ids = <String>[];
      final mock = MockClient((request) async {
        ids.add(request.headers[requestIdHeaderName]!);
        return _encodedResponse(HealthStatus(), ZenTransportFormat.json, 200);
      });
      final client = ZenClient(
        baseUrl: 'http://host',
        format: ZenTransportFormat.json,
        httpClient: mock,
      );

      await client.get(HealthStatus.new, '/a');
      await client.get(HealthStatus.new, '/b');
      await client.get(HealthStatus.new, '/c');

      expect(ids.toSet().length, 3);
      expect(ids[0], endsWith('-1'));
      expect(ids[1], endsWith('-2'));
      expect(ids[2], endsWith('-3'));
    });
  });

  group('ZenClient session recovery on 401', () {
    /// A server that answers 401 until [renewed] is set, then 200. Records every path it saw.
    ZenClient clientAgainstExpiringSession({
      required List<String> seen,
      required bool Function() renewed,
      Future<bool> Function()? recover,
    }) {
      final mock = MockClient((request) async {
        seen.add(request.url.path);
        if (!renewed()) {
          return _encodedResponse(ZenError(code: 'unauthorized'), ZenTransportFormat.json, 401);
        }
        return _encodedResponse(
          HealthStatus(status: 'ok', service: 'zen-demo-server'),
          ZenTransportFormat.json,
          200,
        );
      });
      return ZenClient(
        baseUrl: 'http://host',
        format: ZenTransportFormat.json,
        httpClient: mock,
        recoverSession: recover,
      );
    }

    test('a 401 is renewed and the request replayed once', () async {
      // The gap this closes: the access token lives an hour, the refresh token seven days, and
      // nothing spent the difference. Mid-session the hour would run out and every later call
      // failed until the app was restarted - on the web, until the user signed in again.
      var renewed = false;
      final seen = <String>[];
      final client = clientAgainstExpiringSession(
        seen: seen,
        renewed: () => renewed,
        recover: () async {
          renewed = true;
          return true;
        },
      );

      final result = await client.get(HealthStatus.new, '/api/v1/demo/profile');

      expect(result.isSuccess, isTrue, reason: 'the replay after renewal must succeed');
      expect(seen, ['/api/v1/demo/profile', '/api/v1/demo/profile']);
    });

    test('a failed renewal surfaces the original 401 without a second attempt', () async {
      final seen = <String>[];
      final client = clientAgainstExpiringSession(
        seen: seen,
        renewed: () => false,
        recover: () async => false,
      );

      final result = await client.get(HealthStatus.new, '/api/v1/demo/profile');

      // The session really is over. Replaying anyway would spend the caller's rate-limit budget
      // proving it twice.
      expect(result.isFailure, isTrue);
      expect(seen, ['/api/v1/demo/profile']);
    });

    test('a persistent 401 is not retried forever', () async {
      var recoveries = 0;
      final seen = <String>[];
      final client = clientAgainstExpiringSession(
        seen: seen,
        renewed: () => false,
        recover: () async {
          recoveries++;
          return true; // claims success, but the server keeps refusing
        },
      );

      final result = await client.get(HealthStatus.new, '/api/v1/demo/profile');

      expect(result.isFailure, isTrue);
      expect(recoveries, 1);
      expect(seen.length, 2, reason: 'one original, one replay, and then it stops');
    });

    test('without a callback the 401 is returned exactly as before', () async {
      final seen = <String>[];
      final client = clientAgainstExpiringSession(seen: seen, renewed: () => false);

      final result = await client.get(HealthStatus.new, '/api/v1/demo/profile');

      expect(result.isFailure, isTrue);
      expect(seen.length, 1);
    });

    test('concurrent 401s share one renewal', () async {
      // Five screens firing at once must not fire five refreshes: the refresh endpoint sits in the
      // rate limiter's credential bucket at 10/min, so a client recovering in parallel would
      // throttle itself out of recovering.
      var renewed = false;
      var recoveries = 0;
      final seen = <String>[];
      final client = clientAgainstExpiringSession(
        seen: seen,
        renewed: () => renewed,
        recover: () async {
          recoveries++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          renewed = true;
          return true;
        },
      );

      final results = await Future.wait([
        client.get(HealthStatus.new, '/a'),
        client.get(HealthStatus.new, '/b'),
        client.get(HealthStatus.new, '/c'),
      ]);

      expect(results.every((r) => r.isSuccess), isTrue);
      expect(recoveries, 1);
    });

    test('the renewal call itself is not caught in the retry loop', () async {
      // The recovery callback goes back through this same client (that is how an app wires it), so
      // its own 401 must not trigger another recovery - otherwise a dead session recurses.
      var recoveries = 0;
      late final ZenClient client;
      final mock = MockClient((request) async {
        return _encodedResponse(ZenError(code: 'unauthorized'), ZenTransportFormat.json, 401);
      });
      client = ZenClient(
        baseUrl: 'http://host',
        format: ZenTransportFormat.json,
        httpClient: mock,
        recoverSession: () async {
          recoveries++;
          final refreshed = await client.post(HealthStatus.new, '/api/v1/auth/refresh');
          return refreshed.isSuccess;
        },
      );

      final result = await client.get(HealthStatus.new, '/api/v1/demo/profile');

      expect(result.isFailure, isTrue);
      expect(recoveries, 1, reason: 'the nested refresh must not start a second recovery');
    });
  });
}
