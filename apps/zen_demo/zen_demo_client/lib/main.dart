import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_secure_store/zen_secure_store.dart';
import 'package:zen_transport/zen_transport.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import 'src/app.dart';
import 'src/auth_deep_links.dart';
import 'src/demo_repository.dart';
import 'src/providers.dart';

/// Wires the reference app to the real backend. One session [http.Client]
/// ([createSessionClient], the compile-time platform seam: a native cookie jar or a credentialed
/// browser client) is shared by the identity repository and the demo repository, so the session
/// cookie set at login is resent on every later call - including the auth-gated /demo/profile,
/// the round trip that fails off-web without the jar.
///
/// The base URL is the compile-time [zenApiUrl] (ZEN_API_URL); config stays compile-time.
///
/// The session is also made to survive the app being closed, on the platforms where that does not
/// happen by itself. A browser persists its own cookies; a native process loses everything, so
/// before this a user signed in again on every launch. [SecureTokenStore] keeps the refresh token
/// in the platform keystore and [IdentitySessionStore] spends it on the next start.
void main() {
  // Plugins are reached over platform channels, and the keystore is a plugin, so the binding has
  // to exist before the store is constructed.
  WidgetsFlutterBinding.ensureInitialized();

  // `zenIsWeb` is a const, so this whole branch folds away at compile time: a web build carries
  // no keystore code, and a native build carries no dead check. This is the same compile-time
  // platform selection the codec and session seams use (STANDARDS "Client configuration").
  //
  // Null on web is not a gap: the browser already persists the session cookies itself, and the
  // web session client ignores the store for exactly that reason.
  final TokenStore? tokens = zenIsWeb ? null : SecureTokenStore();
  final ZenSessionClient session = createSessionClient(store: tokens);

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

  // The 401 -> renew -> replay loop, wired once and shared by every repository.
  //
  // The access token lives an hour; the refresh token behind it lives seven days. Nothing spent
  // the difference: the session was resumed at launch on native and never on the web, so an app
  // left open past the hour saw every call fail until it was restarted. The closure is late-bound
  // for the same reason the language one is - it names a repository built on the client it is
  // being handed to, and it is only ever called during a request, by which time both exist.
  late final SupabaseIdentityRepository identityRepository;
  Future<bool> recoverSession() async =>
      (await identityRepository.refreshSession()).isSuccess;

  identityRepository = SupabaseIdentityRepository(
    client: ZenClient(
      baseUrl: zenApiUrl,
      httpClient: session,
      language: () => container.read(localeProvider).languageCode,
      recoverSession: recoverSession,
    ),
  );
  final demoRepository = DemoRepository(
    baseUrl: zenApiUrl,
    session: session,
    recoverSession: recoverSession,
  );

  container = ProviderContainer(
    overrides: [
      identityRepositoryProvider.overrideWithValue(identityRepository),
      demoRepositoryProvider.overrideWithValue(demoRepository),
      // The SAME client the repositories use, not another one: the store restores the refresh
      // cookie into this jar, and a second client would restore it into a jar nobody sends from.
      sessionClientProvider.overrideWithValue(session),
    ],
  );

  // AuthDeepLinks wraps the app rather than sitting inside it: it must outlive every screen, since
  // a confirmation link can arrive at any moment and must be handled the same way wherever the
  // user happens to be. It is inert on the web (conditional import), where links arrive as
  // navigations and the session store has already read them.
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AuthDeepLinks(child: DemoApp()),
    ),
  );
}
