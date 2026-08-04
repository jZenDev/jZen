package zen.transport;

import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import java.util.List;
import java.util.Optional;
import org.eclipse.microprofile.config.Config;
import org.eclipse.microprofile.config.ConfigProvider;

/**
 * Refuses to boot when CORS is configured to send credentials to any origin.
 *
 * <p>jZen's session is a cookie, and {@code access-control-allow-credentials=true} is what lets a
 * cross-origin page send it. Paired with an origin list of {@code *} — or with no list at all,
 * which Quarkus reads as "every origin" — that combination means <em>any</em> website a logged-in
 * user visits can call this API as them and read the reply. It is the browser's same-origin policy
 * switched off for the whole application.
 *
 * <p>The reason this needs a guard rather than a code review is that the origin list arrives from a
 * secret ({@code CORS_ORIGINS}) at deploy time, so the dangerous value is one an operator can
 * introduce without touching the repository — and it is a plausible thing to type while debugging a
 * blocked preflight. It also fails <em>silently</em>: nothing errors, every suite stays green, and
 * the only symptom is that the CORS error the operator was chasing went away.
 *
 * <p>So it fails at startup, loudly, before the first request. On Cloud Run a revision that throws
 * during boot never receives traffic and the previous revision keeps serving — the misconfiguration
 * costs a failed deploy instead of an open API. That is deliberately harsher than logging a
 * warning: a warning in a JSON log stream on a service nobody is watching is not a control.
 *
 * <p>Lives in {@code zen-transport} because that module owns the HTTP boundary and is Jandex-indexed
 * ({@code META-INF/jandex.idx}), so every app assembling jZen inherits the check without wiring it.
 * A module without that index contributes no beans at all and this observer would simply never run.
 */
@ApplicationScoped
public class CorsCredentialsGuard {

  /** The wildcard origin, as it appears in {@code quarkus.http.cors.origins}. */
  static final String WILDCARD = "*";

  private static final String ORIGINS_PROPERTY = "quarkus.http.cors.origins";
  private static final String ENABLED_PROPERTY = "quarkus.http.cors.enabled";
  private static final String CREDENTIALS_PROPERTY =
      "quarkus.http.cors.access-control-allow-credentials";

  void check(@Observes StartupEvent event) {
    Config config = ConfigProvider.getConfig();
    boolean corsEnabled = config.getOptionalValue(ENABLED_PROPERTY, Boolean.class).orElse(false);
    boolean allowCredentials =
        config.getOptionalValue(CREDENTIALS_PROPERTY, Boolean.class).orElse(false);
    if (!corsEnabled || !allowCredentials) {
      return;
    }
    Optional<List<String>> origins = config.getOptionalValues(ORIGINS_PROPERTY, String.class);
    if (isUnrestricted(origins)) {
      throw new IllegalStateException(
          "Refusing to start: quarkus.http.cors.access-control-allow-credentials=true with an"
              + " unrestricted "
              + ORIGINS_PROPERTY
              + " ("
              + origins.map(Object::toString).orElse("unset")
              + "). Credentialed CORS plus any origin lets any site a signed-in user visits call"
              + " this API as them with their session cookie. Set "
              + ORIGINS_PROPERTY
              + " to the exact origins that serve this application (the CORS_ORIGINS secret in"
              + " production), or turn allow-credentials off.");
    }
  }

  /**
   * True when the configured origins amount to "any origin". Three shapes mean that, and only the
   * first is obvious: an explicit {@code *}, an absent property, and an empty list — a
   * {@code CORS_ORIGINS} secret that exists but is blank produces the last of these, which reads
   * like "nothing is allowed" and means the opposite.
   */
  static boolean isUnrestricted(Optional<List<String>> origins) {
    if (origins.isEmpty()) {
      return true;
    }
    List<String> values = origins.get().stream().map(String::trim).filter(v -> !v.isEmpty()).toList();
    return values.isEmpty() || values.contains(WILDCARD);
  }
}
