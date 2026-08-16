import 'package:meta/meta.dart';

import 'auth_url_stub.dart' if (dart.library.js_interop) 'auth_url_web.dart';

/// What a Supabase email link left behind in the URL when it landed the user back on the app.
///
/// Supabase delivers the session it just minted in the URL *fragment*
/// (`#access_token=...&refresh_token=...&type=signup`). A fragment never reaches a server, so the
/// client is the only party that can read it: the backend's `/auth/callback` can do nothing but
/// bounce the browser here with the fragment intact. Reading it is therefore not a convenience,
/// it is the only place in the flow where those tokens are visible at all.
enum ZenAuthLinkKind {
  /// No auth link in the URL — an ordinary app start, which is the overwhelmingly common case.
  none,

  /// A confirmed email (sign-up, magic link, invite) with a usable session: sign the user in.
  session,

  /// A password-recovery link with a usable session: sign in, then require a new password before
  /// letting the user go anywhere. The session is what authorizes the password change.
  recovery,

  /// The email was confirmed but no token came with it, so the user must sign in by hand. This is
  /// the honest fallback for an old link or a mail client that mangled the fragment; the backend's
  /// `?auth=email-confirmed` flag is what still identifies it.
  confirmedWithoutSession,

  /// Supabase refused the link — expired, already used, or otherwise rejected. [errorCode] carries
  /// its reason (`otp_expired`, `access_denied`, ...) so the UI can say something specific.
  failed,
}

/// The parsed contents of an auth link. Immutable and inert: constructing one performs no work and
/// consumes nothing, so parsing is safe to do anywhere, including in a widget build.
@immutable
final class ZenAuthLink {
  /// What kind of landing this is.
  final ZenAuthLinkKind kind;

  /// The Supabase access token, when the link carried one.
  final String? accessToken;

  /// The Supabase refresh token. Absent on some link types; without it the session simply cannot
  /// be refreshed silently and ends when the access token expires.
  final String? refreshToken;

  /// Supabase's machine-readable reason, when [kind] is [ZenAuthLinkKind.failed].
  final String? errorCode;

  const ZenAuthLink._({required this.kind, this.accessToken, this.refreshToken, this.errorCode});

  /// A landing with nothing to consume.
  static const ZenAuthLink none = ZenAuthLink._(kind: ZenAuthLinkKind.none);

  /// A link that could not be used — either the provider said so in the URL, or the exchange for
  /// a session was refused. Both mean the same thing to a user: this link is spent, ask for a new
  /// one.
  const ZenAuthLink.rejected({this.errorCode})
    : kind = ZenAuthLinkKind.failed,
      accessToken = null,
      refreshToken = null;

  /// Whether this link carries tokens worth exchanging for a session.
  bool get hasSession => accessToken != null && accessToken!.isNotEmpty;

  /// Whether the user must set a new password before continuing.
  bool get requiresNewPassword => kind == ZenAuthLinkKind.recovery;

  /// Parses [uri]. Off the web there is no such URL, so `Uri.base` is a file path and this
  /// returns [none] — the flow degrades to "confirm in a browser, then sign in", which is what
  /// a native build does today (native deep linking is tracked separately).
  factory ZenAuthLink.parse(Uri uri) {
    // Supabase reports failures in the fragment for the implicit flow and in the query for some
    // provider redirects. Both are read, because which one arrives is not ours to decide.
    final fragment = _splitQuery(uri.fragment);
    final query = uri.queryParameters;

    final error =
        fragment['error_code'] ?? fragment['error'] ?? query['error_code'] ?? query['error'];
    if (error != null && error.isNotEmpty) {
      return ZenAuthLink._(kind: ZenAuthLinkKind.failed, errorCode: error);
    }

    final accessToken = fragment['access_token'];
    if (accessToken != null && accessToken.isNotEmpty) {
      // `type` distinguishes recovery from every other confirmation. An unknown or missing type is
      // treated as an ordinary sign-in: a link that produced a valid session should not strand the
      // user just because Supabase added a type this version has not heard of.
      final kind = fragment['type'] == 'recovery'
          ? ZenAuthLinkKind.recovery
          : ZenAuthLinkKind.session;
      return ZenAuthLink._(
        kind: kind,
        accessToken: accessToken,
        refreshToken: _emptyToNull(fragment['refresh_token']),
      );
    }

    if (query['auth'] == 'email-confirmed') {
      return const ZenAuthLink._(kind: ZenAuthLinkKind.confirmedWithoutSession);
    }
    return none;
  }

  /// Parses the URL the app was opened with.
  factory ZenAuthLink.current() => ZenAuthLink.parse(Uri.base);

  /// Strips the tokens and the `?auth` flag from the browser's address bar, keeping the page in
  /// place. Call it once the link has been consumed: it stops the token from sitting in the URL,
  /// browser history, and anything the user might copy or share, and stops a page reload from
  /// replaying a landing the app has already handled. A no-op off the web.
  static void clearFromUrl() => clearAuthLinkFromUrl();

  static Map<String, String> _splitQuery(String raw) {
    if (raw.isEmpty) return const {};
    try {
      return Uri.splitQueryString(raw);
    } on FormatException {
      // A fragment that is not a query string (a client-side route, say) is not an auth link.
      return const {};
    }
  }

  static String? _emptyToNull(String? value) => (value == null || value.isEmpty) ? null : value;
}
