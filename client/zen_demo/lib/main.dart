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
/// The base URL is the compile-time [zenApiUrl] (ZEN_API_URL); config stays compile-time (TA-7).
void main() {
  final http.Client session = createSessionClient();

  final identityRepository = SupabaseIdentityRepository(
    client: ZenClient(baseUrl: zenApiUrl, httpClient: session),
  );
  final demoRepository = DemoRepository(baseUrl: zenApiUrl, session: session);

  runApp(
    ProviderScope(
      overrides: [
        identityRepositoryProvider.overrideWithValue(identityRepository),
        demoRepositoryProvider.overrideWithValue(demoRepository),
      ],
      child: const DemoApp(),
    ),
  );
}
