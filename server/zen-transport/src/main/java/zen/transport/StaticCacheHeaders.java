package zen.transport;

import io.vertx.core.http.HttpHeaders;
import io.vertx.ext.web.Router;
import io.vertx.ext.web.RoutingContext;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;

/**
 * Makes a new deploy visible to returning browsers.
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
 * the header to {@code no-cache} — "revalidate before using the cached copy". The static handler
 * already sends an {@code ETag}, so revalidation is a cheap conditional request answered with 304
 * when nothing changed: no staleness, and no re-download of the large Wasm/CanvasKit payloads.
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

  void install(@Observes Router router) {
    router
        .route()
        .order(Integer.MIN_VALUE) // run before the static-resource handler
        .handler(
            rc -> {
              if (mustRevalidate(rc.normalizedPath())) {
                rc.addHeadersEndHandler(
                    v -> rc.response().putHeader(HttpHeaders.CACHE_CONTROL, "no-cache"));
              }
              rc.next();
            });
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
