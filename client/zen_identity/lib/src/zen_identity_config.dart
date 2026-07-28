/// Compile-time configuration for zen_identity.
///
/// Client config stays compile-time (docs/architecture/STANDARDS.md): a
/// `String.fromEnvironment` constant so the toolchain can tree-shake per build. Override with
/// `--define=ZEN_API_URL=https://api.example.com`.
const String zenApiUrl = String.fromEnvironment(
  'ZEN_API_URL',
  defaultValue: 'http://localhost:8080',
);

/// Where this build wants confirmation and recovery emails to send the user back to.
///
/// Empty — the default, and what every web build uses — means "wherever the server sends people
/// by default", which for a web client is the same origin it was served from. A native build has
/// no such luck: an email link cannot open a phone app by URL, so that build defines its own
/// scheme at compile time, e.g.
/// `--dart-define=ZEN_AUTH_REDIRECT_URI=zendemo://auth-callback`.
///
/// Compile-time, like every other client setting (docs/architecture/STANDARDS.md): which build
/// this is decides the answer, and it cannot change while the app runs. The server accepts the
/// value only on an exact match with one of its configured targets, so defining it here is a
/// request, not a decision — the pair must be configured together or registration fails loudly.
const String zenAuthRedirectUri = String.fromEnvironment('ZEN_AUTH_REDIRECT_URI');
