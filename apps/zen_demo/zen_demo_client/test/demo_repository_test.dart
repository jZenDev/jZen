import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zen_transport/zen_transport.dart';

import 'package:zen_demo_client/src/demo_repository.dart';

/// Unit tests for DemoRepository with a stubbed http.Client (the injectable session client),
/// mirroring DartZen's api_client_test.dart. The live stack is exercised by the e2e suite;
/// here we assert the wiring: correct path, method, Accept-Language, forced transport format,
/// and typed parse/error handling. No live server.
void main() {
  group('DemoRepository', () {
    test('ping(json) GETs /api/v1/demo/ping with json format and Accept-Language', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          '{"message":"Server is alive","timestampMs":"1"}',
          200,
          headers: {'content-type': 'application/json', 'x-zen-transport': 'json'},
        );
      });
      final repo = DemoRepository(baseUrl: 'http://localhost:8080', session: client);

      final result = await repo.ping(format: ZenTransportFormat.json, language: 'en');

      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/v1/demo/ping');
      expect(seen.headers['X-Zen-Transport'], 'json');
      expect(seen.headers['Accept-Language'], 'en');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.message, 'Server is alive');
    });

    test('ping(protobuf) forces the protobuf transport header', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        final body = Ping(message: 'Server is alive').writeToBuffer();
        return http.Response.bytes(
          body,
          200,
          headers: {'content-type': 'application/x-protobuf', 'x-zen-transport': 'protobuf'},
        );
      });
      final repo = DemoRepository(baseUrl: 'http://localhost:8080', session: client);

      final result = await repo.ping(format: ZenTransportFormat.protobuf, language: 'uk');

      expect(seen.headers['X-Zen-Transport'], 'protobuf');
      expect(seen.headers['Accept-Language'], 'uk');
      expect(result.isSuccess, isTrue);
    });

    test('terms GETs /api/v1/demo/terms with Accept-Language', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          '{"content":"# Terms","contentType":"text/markdown"}',
          200,
          headers: {'content-type': 'application/json', 'x-zen-transport': 'json'},
        );
      });
      final repo = DemoRepository(baseUrl: 'http://localhost:8080', session: client);

      final result = await repo.terms(language: 'uk');

      expect(seen.url.path, '/api/v1/demo/terms');
      expect(seen.headers['Accept-Language'], 'uk');
      expect(result.dataOrNull?.contentType, 'text/markdown');
    });

    test('profile surfaces a ZenError on 401 (the demo error path)', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"code":"unauthorized","message":"Authentication required"}',
          401,
          headers: {'content-type': 'application/json', 'x-zen-transport': 'json'},
        );
      });
      final repo = DemoRepository(baseUrl: 'http://localhost:8080', session: client);

      final result = await repo.profile();

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, isNotEmpty);
    });
  });
}
