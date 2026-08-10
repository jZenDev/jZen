package zen.transport;

import io.vertx.core.http.HttpHeaders;
import io.vertx.core.http.HttpMethod;
import io.vertx.ext.web.Router;
import io.vertx.ext.web.RoutingContext;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Makes a new deploy visible to returning browsers, and makes a revalidation able to succeed.
 *
 * <p>Quarkus serves static resources (the baked-in web app and admin bundle) with
 * {@code Cache-Control: public, immutable, max-age=86400}. {@code immutable} tells the browser never
 * to revalidate — correct for content-hashed filenames, wrong for the frontends' <b>fixed-name</b>
 * entry and code files. Flutter web does not hash {@code main.dart.wasm}, {@code flutter_bootstrap.js},
 * {@code index.html}, etc., so a redeploy that changes them is invisible for up to a day: the browser
 * keeps serving the cached copy without asking. (This is why a client fix can be deployed yet not
 * appear until the cache expires.)
 *
 * <p>This installs an early Vert.x route that, for exactly those fixed-name entry files, overrides
 * the header to {@code no-cache} — "revalidate before using the cached copy".
 *
 * <h2>Why the validator is ours and not the static handler's</h2>
 *
 * <p>Telling a browser to revalidate is only half a mechanism: the revalidation has to be able to
 * come back <em>empty</em>. It could not. The static handler sends <b>no {@code ETag} at all</b>, and
 * the {@code Last-Modified} it does send is the moment <em>this process</em> started, not the moment
 * the bytes were built — the resources are embedded in the binary, so they have no file timestamp of
 * their own to report. jZen runs on Cloud Run at {@code --min-instances=0} (STANDARDS "Deployment
 * model"), where the container is replaced around two dozen times a day, so that value moved
 * constantly and a conditional request could <b>never</b> succeed. Every returning visitor
 * re-downloaded the whole app: measured in production, {@code main.dart.wasm} alone was 93% of every
 * byte the service had ever sent.
 *
 * <p>So this class supplies the validator itself: a strong {@code ETag} built from
 * {@code zen.build.id} — a stamp filtered in at package time and overridden at deploy with the
 * commit SHA (see {@code META-INF/microprofile-config.properties}). One value for every static
 * resource is not an approximation: the frontends are baked into the binary, so a resource's bytes
 * can only change when the build does. Hashing the resources at boot would be the alternative and a
 * worse defect — 44 MiB read and digested on a cold start to answer a question the build already
 * answered.
 *
 * <p><b>{@code If-None-Match} is answered here, before the static handler reads anything</b>, which
 * is also what makes the precedence rule hold. RFC 9110 §13.2.2 requires a server that evaluates
 * {@code If-None-Match} to ignore {@code If-Modified-Since}, and a real browser revalidates with
 * <em>both</em> headers. Since a matching {@code If-None-Match} ends the response right here, the
 * static handler's process-start {@code Last-Modified} is never consulted — it cannot turn a 304
 * back into a 200.
 *
 * <p>The validator is attached to the long-cached resources too, not only the {@code no-cache} entry
 * files. {@code canvaskit/*} and {@code assets/*} keep their day of {@code immutable} freshness; when
 * it expires they revalidate, and that revalidation now returns 304 instead of re-sending 3.58 MiB.
 *
 * <h2>Which paths this applies to</h2>
 *
 * <p>A build-stable validator is only ever correct for build-stable bytes, so it must not reach a
 * dynamic response — a 304 for a changing payload is a served-stale bug, not a saving. The route runs
 * before everything, so the dynamic roots are named in {@link #DYNAMIC_PREFIXES} and excluded:
 * {@code /api/} (JAX-RS and the WebSocket), {@code /auth/} (the OAuth callback), {@code /.well-known/}
 * (the app-association documents) and {@code /q/} (Quarkus' own endpoints). <b>Adding a JAX-RS root
 * outside those prefixes means adding it here</b>; {@code StaticCacheHeadersWiringTest} in the app
 * asserts the live dynamic endpoints carry no {@code ETag}, so that omission fails a suite rather
 * than silently caching a dynamic response.
 *
 * <p>Everything else keeps the default long cache. That includes the admin panel's
 * {@code /admin/assets/*}, which Vite <em>does</em> content-hash, and the Flutter
 * {@code canvaskit/*} and {@code assets/*}, which change only on an SDK upgrade.
 *
 * <p>Lives in {@code zen-transport} (the HTTP seam, Jandex-indexed) so any app that serves a
 * frontend same-origin inherits correct caching. Uses a header-end handler so it overrides the
 * value the static handler sets, rather than racing it.
 */
@ApplicationScoped
public class StaticCacheHeaders {

  /**
   * What Quarkus' static-resource handler puts on everything this class does not override. Repeated
   * here only so a 304 can restate it — a revalidation that answered without a freshness lifetime
   * would leave the browser revalidating on every subsequent load.
   * {@code StaticCacheHeadersWiringTest} compares the 200 and the 304 for the same resource against
   * an assembled application, so a Quarkus default that moved would fail a suite rather than
   * quietly halve the value of every revalidation.
   */
  static final String LONG_CACHE = "public, immutable, max-age=86400";

  static final String NO_CACHE = "no-cache";

  /**
   * Path roots served by something other than the static handler. See the class javadoc: these are
   * excluded because a build-stable validator on a dynamic response would serve stale data.
   */
  private static final List<String> DYNAMIC_PREFIXES = List.of("/api/", "/auth/", "/.well-known/", "/q/");

  private final String etag;

  @Inject
  public StaticCacheHeaders(@ConfigProperty(name = "zen.build.id") String buildId) {
    this.etag = etagOf(buildId);
  }

  void install(@Observes Router router) {
    router
        .route()
        // Before the static-resource handler, which is what lets a 304 be answered without the
        // resource being read at all — but AFTER SecurityHeaders, which sits at Integer.MIN_VALUE.
        // Ending the response here skips every route that has not yet run, and two routes at the
        // same order run in registration order, which nothing here controls. One step later makes
        // it deterministic, so a 304 carries the security headers exactly as a 200 does.
        .order(Integer.MIN_VALUE + 1)
        .handler(this::applyValidator);
  }

  private void applyValidator(RoutingContext rc) {
    String path = rc.normalizedPath();
    HttpMethod method = rc.request().method();
    if (!isStaticResourcePath(path) || (method != HttpMethod.GET && method != HttpMethod.HEAD)) {
      rc.next();
      return;
    }

    String cacheControl = mustRevalidate(path) ? NO_CACHE : LONG_CACHE;

    if (matchesEtag(rc.request().getHeader(HttpHeaders.IF_NONE_MATCH), etag)) {
      // Ends here, so If-Modified-Since is never evaluated (RFC 9110 §13.2.2). See the javadoc.
      rc.response()
          .setStatusCode(304)
          .putHeader(HttpHeaders.ETAG, etag)
          .putHeader(HttpHeaders.CACHE_CONTROL, cacheControl)
          .end();
      return;
    }

    rc.addHeadersEndHandler(
        v -> {
          // Only a served resource gets a validator. A 404 that handed one out would let the
          // browser hold an ETag for a path that has no bytes behind it yet.
          if (rc.response().getStatusCode() == 200) {
            rc.response().putHeader(HttpHeaders.ETAG, etag);
          }
          if (mustRevalidate(path)) {
            rc.response().putHeader(HttpHeaders.CACHE_CONTROL, NO_CACHE);
          }
        });
    rc.next();
  }

  /**
   * The strong entity-tag for a build stamp: the stamp, quoted, with anything outside the
   * entity-tag character set replaced. {@code GIT_SHA} and a timestamp are both already safe; the
   * scrub is there so an operator-supplied {@code ZEN_BUILD_ID} cannot emit a header a proxy would
   * reject or, worse, one that lets a value close the quoted string.
   */
  static String etagOf(String buildId) {
    String safe = buildId == null ? "" : buildId.replaceAll("[^A-Za-z0-9._~:@+-]", "-");
    return "\"" + safe + "\"";
  }

  /**
   * True when the {@code If-None-Match} header names {@code etag}. The header is a list and its
   * members may be weak ({@code W/"..."}); {@code *} matches whatever the server holds. Weak and
   * strong compare equal here because the comparison RFC 9110 §13.1.2 prescribes for
   * {@code If-None-Match} is the weak one.
   */
  static boolean matchesEtag(String ifNoneMatch, String etag) {
    if (ifNoneMatch == null || ifNoneMatch.isBlank()) {
      return false;
    }
    for (String candidate : ifNoneMatch.split(",")) {
      String value = candidate.trim();
      if (value.startsWith("W/")) {
        value = value.substring(2).trim();
      }
      if (value.equals("*") || value.equals(etag)) {
        return true;
      }
    }
    return false;
  }

  /**
   * True for paths the static handler serves. Everything is, except the dynamic roots — see the
   * class javadoc for why this is a list of exclusions rather than a list of resources.
   */
  static boolean isStaticResourcePath(String path) {
    if (path == null || path.isEmpty() || !path.startsWith("/")) {
      return false;
    }
    for (String prefix : DYNAMIC_PREFIXES) {
      if (path.startsWith(prefix) || path.equals(prefix.substring(0, prefix.length() - 1))) {
        return false;
      }
    }
    return true;
  }

  /**
   * True for the fixed-name SPA entry and code files a redeploy changes: any directory index
   * ({@code /}, {@code /admin/}, or {@code .../index.html}), and the Flutter bootstrap/runtime files.
   */
  static boolean mustRevalidate(String path) {
    if (path == null) {
      return false;
    }
    if (path.endsWith("/") || path.endsWith("/index.html")) {
      return true;
    }
    String name = path.substring(path.lastIndexOf('/') + 1);
    return switch (name) {
      case "flutter_bootstrap.js",
          "flutter.js",
          "flutter_service_worker.js",
          "main.dart.js",
          "main.dart.mjs",
          "main.dart.wasm",
          "version.json" -> true;
      default -> false;
    };
  }
}
