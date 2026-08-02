package zen.identity.auth;

import jakarta.annotation.security.PermitAll;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.Optional;
import java.util.regex.Pattern;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Serves the two association files that let an operating system verify an {@code https://} link
 * belongs to this application, so a confirmation or recovery link can open the app itself.
 *
 * <p><strong>Why this exists: a custom scheme cannot be owned.</strong> {@code zendemo://} is a
 * private-use URI scheme, and RFC 8252 §8.6 is explicit that no application can claim one
 * exclusively — any app on the device may register the same one. That would be a small matter if
 * the link carried a one-time code, but it does not: jZen uses the implicit fragment flow
 * (ADR-018), so the URL contains a live access <em>and</em> refresh token. An application that wins
 * the scheme race receives them and has the account, while every signal the victim can see says
 * they are safe — they asked for the email, it came from the right sender, they followed their own
 * link. The server-side allowlist (ADR-019) does not help here and it is worth being clear why: it
 * checks which return address may be <em>requested</em>, and the attacker requests nothing. They
 * listen for the address the real app already asked for.
 *
 * <p>App Links (Android) and Universal Links (iOS) fix it at the root, by making the association
 * verifiable rather than declared: the link is an ordinary {@code https://} URL, and the OS opens
 * it in an app only after fetching one of these files from the domain and finding that app named.
 * A hostile app cannot forge that, because it cannot serve files from this origin.
 *
 * <h2>Configuration, and why an absent file is better than an empty one</h2>
 *
 * <p>Both endpoints answer <strong>404 until they are configured</strong>, rather than serving an
 * empty or placeholder document. This is deliberate. Android and iOS both <em>cache</em> the
 * outcome of verification, so a file that is present but does not name the app teaches the OS that
 * the association failed — and it will not re-check on a schedule that helps anyone. A 404 leaves
 * the association simply unestablished, which is a state the platforms retry from cleanly. The
 * empty default also means an application that never adopts App Links serves nothing extra.
 *
 * <ul>
 *   <li>{@code auth.applinks.android-package} + {@code auth.applinks.android-fingerprints} — the
 *       application id and the SHA-256 fingerprints of every signing certificate that must be
 *       admitted. There is usually more than one: a debug keystore and a release key sign
 *       different builds of the same application, and both need listing or the build a developer
 *       actually runs fails verification.
 *   <li>{@code auth.applinks.apple-app-ids} — {@code <TeamID>.<bundle-id>} for each iOS app.
 * </ul>
 *
 * <p>Both files must be served over HTTPS, as {@code application/json}, from the domain root, with
 * <strong>no redirect</strong> — a redirect fails verification on both platforms. jZen serves Cloud
 * Run directly (STANDARDS "Deployment model"), which is what makes that achievable here; an edge
 * that rewrote these paths would break the association exactly as it would break the session
 * cookies.
 */
@Path("/.well-known")
@ApplicationScoped
public class WellKnownResource {

  /**
   * Config values land in files the operating system parses, so they are constrained rather than
   * escaped: an application id, a hex fingerprint and a team-qualified bundle id are all drawn
   * from this set. Anything else is a configuration mistake, and rejecting it is better than
   * emitting a document whose meaning depends on how a parser handles a quote.
   */
  private static final Pattern SAFE = Pattern.compile("[A-Za-z0-9._:*-]+");

  @Inject
  @ConfigProperty(name = "auth.applinks.android-package")
  Optional<String> androidPackage;

  @Inject
  @ConfigProperty(name = "auth.applinks.android-fingerprints")
  Optional<List<String>> androidFingerprints;

  @Inject
  @ConfigProperty(name = "auth.applinks.apple-app-ids")
  Optional<List<String>> appleAppIds;

  /**
   * Android's Digital Asset Links file. {@code delegate_permission/common.handle_all_urls} is what
   * grants the named application the right to open this domain's links.
   */
  @GET
  @Path("/assetlinks.json")
  @PermitAll
  @Produces(MediaType.APPLICATION_JSON)
  public Response assetLinks() {
    String pkg = androidPackage.map(String::trim).filter(s -> !s.isEmpty()).orElse(null);
    List<String> prints = clean(androidFingerprints);
    if (pkg == null || prints.isEmpty()) {
      return notConfigured();
    }
    require(pkg);
    prints.forEach(WellKnownResource::require);

    StringBuilder json = new StringBuilder("[{\"relation\":[\"delegate_permission/common.handle_all_urls\"],");
    json.append("\"target\":{\"namespace\":\"android_app\",\"package_name\":\"").append(pkg).append("\",");
    json.append("\"sha256_cert_fingerprints\":[");
    for (int i = 0; i < prints.size(); i++) {
      if (i > 0) {
        json.append(',');
      }
      json.append('"').append(prints.get(i)).append('"');
    }
    json.append("]}}]");
    return Response.ok(json.toString()).build();
  }

  /**
   * Apple's app-site-association file. Note the path has <strong>no extension</strong>, which is
   * required, and iOS fetches it without following redirects.
   *
   * <p>{@code "*"} as the path admits every URL on this domain, which is what jZen wants: the
   * email link lands on {@code /auth/callback}, but narrowing it here would mean editing this file
   * whenever a route moves, and the association is about the domain, not the route.
   */
  @GET
  @Path("/apple-app-site-association")
  @PermitAll
  @Produces(MediaType.APPLICATION_JSON)
  public Response appleAppSiteAssociation() {
    List<String> ids = clean(appleAppIds);
    if (ids.isEmpty()) {
      return notConfigured();
    }
    ids.forEach(WellKnownResource::require);

    StringBuilder json = new StringBuilder("{\"applinks\":{\"details\":[");
    for (int i = 0; i < ids.size(); i++) {
      if (i > 0) {
        json.append(',');
      }
      json.append("{\"appIDs\":[\"").append(ids.get(i)).append("\"],");
      json.append("\"components\":[{\"/\":\"*\"}]}");
    }
    json.append("]}}");
    return Response.ok(json.toString()).build();
  }

  private static List<String> clean(Optional<List<String>> values) {
    return values.orElse(List.of()).stream().map(String::trim).filter(s -> !s.isEmpty()).toList();
  }

  private static void require(String value) {
    if (!SAFE.matcher(value).matches()) {
      throw new IllegalStateException(
          "An App Links configuration value contains characters that do not belong in one."
              + " Check auth.applinks.* — the value is not echoed here.");
    }
  }

  private static Response notConfigured() {
    // 404, not an empty document: see the class javadoc. The platforms cache a failed association.
    return Response.status(Response.Status.NOT_FOUND).build();
  }
}
