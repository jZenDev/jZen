import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_transport/zen_transport.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import 'src/app.dart';
import 'src/demo_repository.dart';
import 'src/providers.dart';

/// Wires the reference app to the real backend. One session [http.Client]
/// ([createSessionClient], the compile-time platform seam: a native cookie jar or a credentialed
/// browser client) is shared by the identity repository and the demo repository, so the session
/// cookie set at login is resent on every later call - including the auth-gated /demo/profile,
/// the round trip that fails off-web without the jar.
///
/// The base URL is the compile-time [zenApiUrl] (ZEN_API_URL); config stays compile-time.
void main() {
  final http.Client session = createSessionClient();

  // The container is built below, but ZenClient only calls this closure when it sends a
  // request - by which time it is assigned. Reading the notifier per request (rather than
  // capturing a value) is what makes a mid-session language switch take effect, and it is
  // what carries the chosen locale into POST /auth/register, where the server seeds
  // users.language and every later localized email follows from it.
  //
  // The provider holds a Locale (it is also MaterialApp.locale, so the same switch re-renders
  // the typed generated strings - ADR-009); the wire wants the language tag, which is the one
  // conversion this seam performs.
  late final ProviderContainer container;
  final identityRepository = SupabaseIdentityRepository(
    client: ZenClient(
      baseUrl: zenApiUrl,
      httpClient: session,
      language: () => container.read(localeProvider).languageCode,
    ),
  );
  final demoRepository = DemoRepository(baseUrl: zenApiUrl, session: session);

  container = ProviderContainer(
    overrides: [
      identityRepositoryProvider.overrideWithValue(identityRepository),
      demoRepositoryProvider.overrideWithValue(demoRepository),
    ],
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const DemoApp()),
  );
}
