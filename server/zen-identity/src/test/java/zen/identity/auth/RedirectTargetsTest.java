package zen.identity.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import zen.identity.AuthException;

/**
 * Unit tests for the email-link return-address allowlist.
 *
 * <p>A plain JUnit test, not a {@code @QuarkusTest}: {@link RedirectTargets} takes its two
 * configuration values through its constructor, so the interesting cases are reachable without a
 * container — and, more to the point, without the single fixed configuration a running application
 * has. That matters here, because the case that went unnoticed in production is precisely the one
 * the assembled app cannot express: a deployment with ADDITIONAL entries configured. An app-level
 * test can only ever exercise its own {@code auth.redirect-uris}, and when that is empty (the
 * default), passing a test proves nothing about a native client.
 */
class RedirectTargetsTest {

  private static final String WEB = "https://app.example.com/auth/callback";
  private static final String NATIVE = "zendemo://auth-callback";

  private static RedirectTargets targets(String... additional) {
    return new RedirectTargets(WEB, Optional.of(List.of(additional)));
  }

  @Test
  void noRequest_getsTheDefault() {
    assertEquals(WEB, targets().resolve(null));
    assertEquals(WEB, targets().resolve(""));
    assertEquals(WEB, targets().resolve("   "));
  }

  @Test
  void theDefaultIsAlwaysAllowed_evenWhenNamedExplicitly() {
    assertEquals(WEB, targets().resolve(WEB));
  }

  @Test
  void aConfiguredNativeScheme_isAllowed() {
    // The deployment case: one backend, a web client and a phone app that cannot share a return
    // address. Without this entry the native client is locked out (400) while the web app is fine.
    assertEquals(NATIVE, targets(NATIVE).resolve(NATIVE));
  }

  @Test
  void anUnconfiguredNativeScheme_isRefused() {
    // The empty-allowlist default, which is what a deployment that forgets AUTH_REDIRECT_URIS has.
    AuthException e = assertThrows(AuthException.class, () -> targets().resolve(NATIVE));
    assertEquals(400, e.status());
    assertEquals("invalid_redirect", e.code());
  }

  @Test
  void severalClients_areEachAllowed() {
    RedirectTargets t = targets(NATIVE, "otherapp://auth");
    assertEquals(NATIVE, t.resolve(NATIVE));
    assertEquals("otherapp://auth", t.resolve("otherapp://auth"));
  }

  @Test
  void surroundingWhitespace_isIgnoredOnBothSides() {
    // Config lists are hand-edited and comma-separated, so " zendemo://auth-callback" is an easy
    // way to configure a value that then never matches. Trimming both sides removes that trap
    // without loosening the match itself.
    assertEquals(NATIVE, targets(" " + NATIVE + " ").resolve(NATIVE));
    assertEquals(NATIVE, targets(NATIVE).resolve("  " + NATIVE + "  "));
  }

  @Test
  void matchingIsExact_notAPrefixOrHostMatch() {
    RedirectTargets t = targets(NATIVE);
    // The attacks exact matching exists to refuse: a prefix rule would admit the first, a host
    // rule the second, and a token for someone else's account would be mailed to the attacker.
    for (String evil :
        List.of(
            "zendemo://auth-callback.evil.example",
            "zendemo://auth-callback/../elsewhere",
            "zendemo://auth-callback?next=https://evil.example",
            "zendemo://auth-callbackX",
            "ZENDEMO://auth-callback")) {
      assertThrows(AuthException.class, () -> t.resolve(evil), evil + " must not be allowed");
    }
  }

  @Test
  void theRefusal_doesNotEchoTheRequestedValue() {
    // Untrusted text on its way into logs and a client-facing message.
    AuthException e =
        assertThrows(AuthException.class, () -> targets().resolve("zendemo://evil.example"));
    assertTrue(
        e.getMessage() == null || !e.getMessage().contains("evil.example"),
        "the rejection must not repeat the refused address");
  }

  @Test
  void blankAndDuplicateEntries_areDropped() {
    // A trailing comma in the config yields an empty entry; left in, it would make resolve("")
    // ambiguous rather than simply returning the default.
    RedirectTargets t = targets("", "   ", NATIVE, NATIVE);
    assertEquals(List.of(WEB, NATIVE), t.allowed());
    assertEquals(WEB, t.resolve(""));
  }

  @Test
  void theDefaultIsFirst_andNotDuplicatedWhenAlsoListed() {
    assertEquals(List.of(WEB, NATIVE), targets(WEB, NATIVE).allowed());
  }
}
