package zen.identity.auth;

import zen.identity.AuthException;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.util.List;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Decides where an email link is allowed to send the user back to.
 *
 * <p>One backend serves every client an application has — the web app at its URL, and (once the
 * native builds exist) a phone app reachable only through its own scheme. They cannot share one
 * return address, so the client has to name the one it wants. That request is
 * <strong>attacker-controlled input</strong>, and it is the most dangerous kind: Supabase mails a
 * link that carries a live session token in its fragment, so a value taken on trust would let
 * anyone have a token for someone else's account delivered to a destination they control. The
 * account holder need only click their own, entirely genuine-looking, email.
 *
 * <p>So a requested target is accepted only by <strong>exact match</strong> against the configured
 * list. Deliberately not a prefix or host match: {@code zen://auth} as a prefix also admits
 * {@code zen://auth.evil.example}, and a host check on {@code app.example.com} says nothing about
 * the path a token would land on. Exact match has no such edges — a new client is a new
 * configuration entry, which is a deployment decision, made by a person, once.
 *
 * <p>Configuration:
 *
 * <ul>
 *   <li>{@code auth.redirect-uri} — the default, used when a client asks for nothing. This is the
 *       web app's own callback, and it is always allowed.
 *   <li>{@code auth.redirect-uris} — additional permitted targets, comma-separated. Empty until an
 *       application ships a client that needs one, which is the safe default: with no entries, the
 *       only reachable destination is the server's own.
 * </ul>
 */
@ApplicationScoped
public class RedirectTargets {

  private final String defaultTarget;
  private final List<String> allowed;

  @Inject
  public RedirectTargets(
      @ConfigProperty(name = "auth.redirect-uri") String defaultTarget,
      @ConfigProperty(name = "auth.redirect-uris") Optional<List<String>> additional) {
    this.defaultTarget = defaultTarget;
    // The default is a member of its own allowlist: a client that names the web callback
    // explicitly is asking for something already permitted, and should not be refused for saying
    // out loud what it would have got by staying silent.
    this.allowed =
        java.util.stream.Stream.concat(
                java.util.stream.Stream.of(defaultTarget), additional.orElse(List.of()).stream())
            .map(String::trim)
            .filter(s -> !s.isEmpty())
            .distinct()
            .toList();
  }

  /**
   * Returns the target to hand Supabase for {@code requested}, or throws when it is not permitted.
   *
   * <p>The rejection deliberately does not echo the value back. It is untrusted text on its way
   * into logs and a client-facing message, and a caller that sent it already knows what it sent —
   * repeating it buys nothing and hands an attacker a way to write their own strings into places
   * they do not belong.
   */
  public String resolve(String requested) {
    if (requested == null || requested.isBlank()) {
      return defaultTarget;
    }
    String candidate = requested.trim();
    if (allowed.contains(candidate)) {
      return candidate;
    }
    throw new AuthException(
        400, "invalid_redirect", "That return address is not configured for this application.");
  }

  /** The permitted targets, default first. Exposed for diagnostics and tests, not for matching. */
  public List<String> allowed() {
    return allowed;
  }
}
