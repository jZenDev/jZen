import 'package:test/test.dart';
import 'package:zen_identity/zen_identity.dart';

/// The parser's job is to read what Supabase actually sends. Each case below is a URL shape the
/// deployed app can genuinely be opened with, not an invented one.
void main() {
  test('a sign-up confirmation carries a session to exchange', () {
    final link = ZenAuthLink.parse(
      Uri.parse(
        'https://app.example/#access_token=at&expires_in=3600&refresh_token=rt'
        '&token_type=bearer&type=signup',
      ),
    );

    expect(link.kind, ZenAuthLinkKind.session);
    expect(link.hasSession, true);
    expect(link.accessToken, 'at');
    expect(link.refreshToken, 'rt');
    expect(link.requiresNewPassword, false);
  });

  test('a recovery link is a session that still owes a new password', () {
    final link = ZenAuthLink.parse(
      Uri.parse('https://app.example/#access_token=at&refresh_token=rt&type=recovery'),
    );

    expect(link.kind, ZenAuthLinkKind.recovery);
    expect(link.hasSession, true);
    expect(link.requiresNewPassword, true);
  });

  test('an unknown link type with a valid session still signs in', () {
    // Supabase adding a type this version has not heard of must not strand a user holding a
    // perfectly good session.
    final link = ZenAuthLink.parse(
      Uri.parse('https://app.example/#access_token=at&type=something_new'),
    );

    expect(link.kind, ZenAuthLinkKind.session);
    expect(link.refreshToken, isNull, reason: 'absent is null, not an empty string');
  });

  test('a rejected link reports why, from the fragment or the query', () {
    final fromFragment = ZenAuthLink.parse(
      Uri.parse(
        'https://app.example/#error=access_denied&error_code=otp_expired'
        '&error_description=Email+link+is+invalid+or+has+expired',
      ),
    );
    expect(fromFragment.kind, ZenAuthLinkKind.failed);
    expect(fromFragment.errorCode, 'otp_expired');
    expect(fromFragment.hasSession, false);

    final fromQuery = ZenAuthLink.parse(Uri.parse('https://app.example/?error=access_denied'));
    expect(fromQuery.kind, ZenAuthLinkKind.failed);
    expect(fromQuery.errorCode, 'access_denied');
  });

  test('a confirmation without a token is recognised as needing a manual sign-in', () {
    final link = ZenAuthLink.parse(Uri.parse('https://app.example/?auth=email-confirmed'));

    expect(link.kind, ZenAuthLinkKind.confirmedWithoutSession);
    expect(link.hasSession, false);
  });

  test('an ordinary URL, and a fragment that is not a query, are not auth links', () {
    expect(ZenAuthLink.parse(Uri.parse('https://app.example/')).kind, ZenAuthLinkKind.none);
    expect(ZenAuthLink.parse(Uri.parse('https://app.example/#/dashboard')).kind,
        ZenAuthLinkKind.none);
    expect(ZenAuthLink.parse(Uri.parse('file:///Users/someone/app')).kind, ZenAuthLinkKind.none);
  });

  test('an empty access token counts as no session', () {
    final link = ZenAuthLink.parse(Uri.parse('https://app.example/#access_token=&type=signup'));
    expect(link.hasSession, false);
    expect(link.kind, ZenAuthLinkKind.none);
  });
}
