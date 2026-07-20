@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

// The living end-to-end test stand (ROADMAP step 4). A pure-Dart VM suite (package:test, no
// flutter) so it runs headless and cheap under `dart test` in CI (task test:e2e), yet exercises
// the same zen_transport / SupabaseIdentityRepository code the app uses - including the native
// cookie jar, because the VM is a dart:io platform. No mocks: every call hits the live Quarkus +
// Supabase stack. The base URL is the compile-time zenApiUrl (ZEN_API_URL); pass ZEN_ENV=dev so
// the default codec is JSON.
//
// What it asserts end to end: register + login via Supabase, the session cookie surviving across
// requests (getCurrentIdentity and the auth-gated /demo/profile on a different client sharing the
// jar), a typed round trip in BOTH transport modes, a localized surface (en vs uk), the WebSocket
// echo, an error path returning a ZenError, and logout clearing the session.
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_transport/zen_transport.dart';

import 'package:zen_demo_client/src/demo_repository.dart';

void main() {
  // The base URL comes from the ZEN_API_URL environment variable (the Taskfile sets it to the
  // live server). This is a VM test harness, not the shipped client bundle, so reading it at
  // runtime is fine - TA-7's compile-time-config rule is about tree-shaking the app bundle, and
  // `dart test` does not forward compile-time defines to the compiled test anyway (so a define
  // for ZEN_API_URL would not reach here). Falls back to zenApiUrl.
  final baseUrl = Platform.environment['ZEN_API_URL'] ?? zenApiUrl;
  final email = 'zen-e2e-${DateTime.now().microsecondsSinceEpoch}@example.com';
  const password = 'secret123';

  late http.Client session;
  late SupabaseIdentityRepository identity;
  late DemoRepository demo;

  setUpAll(() async {
    session = createSessionClient();
    identity = SupabaseIdentityRepository(
      client: ZenClient(baseUrl: baseUrl, httpClient: session),
    );
    demo = DemoRepository(baseUrl: baseUrl, session: session);

    // Register a fresh user; with local Supabase auto-confirm this logs in and sets the cookies.
    final registered = await identity.registerWithEmail(email: email, password: password);
    expect(
      registered.isSuccess,
      isTrue,
      reason: 'register should succeed against the live stack: ${registered.errorOrNull?.message}',
    );
  });

  tearDownAll(() {
    session.close();
  });

  test('the session cookie survives across requests (getCurrentIdentity)', () async {
    final current = await identity.getCurrentIdentity();
    expect(current.isSuccess, isTrue);
    final model = current.dataOrNull;
    expect(model, isNotNull, reason: 'the registration cookie must be resent on native');
    expect(model!.id, isNotEmpty);
  });

  test('the auth-gated demo profile works on a client sharing the jar', () async {
    final profile = await demo.profile();
    expect(
      profile.isSuccess,
      isTrue,
      reason: 'the session cookie must reach /demo/profile: ${profile.errorOrNull?.message}',
    );
    expect(profile.dataOrNull!.email, email);
  });

  test('ping round-trips in JSON mode', () async {
    final result = await demo.ping(format: ZenTransportFormat.json, language: 'en');
    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.message, 'Server is alive');
    expect(result.dataOrNull!.timestampMs.toInt(), greaterThan(0));
  });

  test('ping round-trips in Protobuf mode', () async {
    final result = await demo.ping(format: ZenTransportFormat.protobuf, language: 'en');
    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.message, 'Server is alive');
  });

  test('the surface is localized (en vs uk)', () async {
    final en = await demo.ping(format: ZenTransportFormat.json, language: 'en');
    final uk = await demo.ping(format: ZenTransportFormat.json, language: 'uk');
    expect(en.dataOrNull!.message, 'Server is alive');
    expect(uk.dataOrNull!.message, isNot(equals(en.dataOrNull!.message)));

    final termsEn = await demo.terms(language: 'en');
    final termsUk = await demo.terms(language: 'uk');
    expect(termsEn.dataOrNull!.content, contains('Terms of Service'));
    expect(termsUk.dataOrNull!.content, contains('Умови використання'));
  });

  test('the WebSocket echoes a message back', () async {
    final socket = demo.connectWebSocket();
    addTearDown(() => socket.close());
    final echoes = socket.responses(WebSocketMessage.new);
    final first = echoes.first;
    socket.send(WebSocketMessage(type: 'message', payload: 'hello-e2e'));
    final reply = await first.timeout(const Duration(seconds: 10));
    expect(reply.type, 'echo');
    expect(reply.payload, 'hello-e2e');
  });

  test('an anonymous demo profile returns a ZenError', () async {
    final anonSession = createSessionClient();
    addTearDown(anonSession.close);
    final anon = DemoRepository(baseUrl: zenApiUrl, session: anonSession);

    final result = await anon.profile();
    expect(result.isFailure, isTrue);
    expect(result.errorOrNull!.message, isNotEmpty);
  });

  test('logout clears the session', () async {
    final loggedOut = await identity.logout();
    expect(loggedOut.isSuccess, isTrue);

    final current = await identity.getCurrentIdentity();
    expect(current.isSuccess, isTrue);
    expect(current.dataOrNull, isNull, reason: 'logout must clear the session cookie');
  });
}
