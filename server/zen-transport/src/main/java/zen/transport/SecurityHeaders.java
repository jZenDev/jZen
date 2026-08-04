package zen.transport;

import io.vertx.ext.web.Router;
import io.vertx.ext.web.RoutingContext;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;

/**
 * The browser-facing security headers, on every response this server produces.
 *
 * <p><strong>Why this runs on the Vert.x layer and not as a JAX-RS filter.</strong> The two
 * responses that most need a Content-Security-Policy and frame protection are the two that never
 * reach JAX-RS: the Flutter web app at {@code /} and the admin panel at {@code /admin/} are served
 * by Quarkus's static-resource handler, which sits on the Vert.x router well before any JAX-RS
 * provider runs. A {@code ContainerResponseFilter} would have covered the API — the part of the
 * surface with no DOM, no frames and no scripts — and left the two real browser documents bare.
 * This route sees all three paths, which {@code SecurityHeadersTest} asserts one by one rather
 * than trusting the argument.
 *
 * <p>It uses an {@code @Observes Router} route at {@link Integer#MIN_VALUE} rather than a
 * {@code @RouteFilter}, which would mean adding {@code quarkus-vertx-web} to this module for a
 * capability the router already has. {@link StaticCacheHeaders} established the pattern and is the
 * evidence it reaches the static handler: its {@code Cache-Control: no-cache} override is
 * observable on the deployed {@code /}. Both are the same decision — Vert.x, not JAX-RS.
 *
 * <p>The values are written with {@code addHeadersEndHandler} so they are applied as the response
 * is being finalised, after any handler that might set its own, rather than racing whatever runs
 * next. Lives in {@code zen-transport} because that module owns the HTTP boundary (and is
 * Jandex-indexed, without which this bean is never discovered and adds nothing, silently —
 * {@code SecurityHeadersWiringTest} is the guard).
 *
 * <h2>The policy, and what each relaxation costs</h2>
 *
 * <p>A strict {@code default-src 'self'} is the goal and four things stand in the way. Each is
 * named here with what it buys, because a CSP nobody can explain is a CSP that gets widened by the
 * next person who meets a console error.
 *
 * <ul>
 *   <li>{@code 'wasm-unsafe-eval'} in {@code script-src} — jZen delivers the web app as
 *       WebAssembly (ADR-016). Compiling a Wasm module is script execution as far as CSP is
 *       concerned, so without this the app does not start at all. This keyword exists precisely so
 *       that Wasm does not have to be bought with {@code 'unsafe-eval'}, which would also re-enable
 *       {@code eval()} and {@code new Function()} for every script on the page.
 *   <li>{@code 'unsafe-inline'} in {@code style-src} — react-admin's Material UI generates its
 *       styles at runtime and injects them as inline {@code <style>} elements, and Flutter's engine
 *       sets inline styles on the elements it creates. There is no build-time nonce to hand either
 *       of them. This is the weakest of the three relaxations: it is not script execution, and the
 *       attacks it leaves open are exfiltration through crafted selectors rather than code.
 *   <li>{@code blob:} in {@code worker-src} and {@code img-src} — the Wasm renderer runs its
 *       rasterisation on Web Workers created from blob URLs, and decodes images into blobs. Scoped
 *       to those two directives, so it does not widen {@code script-src}.
 *   <li>{@code https://fonts.gstatic.com} in {@code font-src} <b>and {@code connect-src}</b> — the
 *       one cross-origin host left, and the only relaxation this policy makes for a third party.
 *       See below, including why it takes two directives rather than the obvious one.
 * </ul>
 *
 * <h2>The font host needs {@code connect-src}, and {@code font-src} alone is a blank page</h2>
 *
 * <p>This is the trap the whole "verify in a browser" instruction exists for, and it was found
 * there rather than in a test. The Flutter web engine does not load its fonts through CSS
 * {@code @font-face}; it fetches them with {@code fetch()} and hands the bytes to the renderer. CSP
 * governs a {@code @font-face} load with {@code font-src} and a {@code fetch()} with
 * {@code connect-src}, so a policy naming the host in {@code font-src} only allows it in the
 * mechanism the engine does not use and blocks it in the one it does.
 *
 * <p>Measured on the real native image, in Chrome, against the same URL:
 *
 * <pre>
 *   await fetch(robotoUrl)                    -> BLOCKED: Failed to fetch
 *   await new FontFace('probe', url).load()   -> ok
 * </pre>
 *
 * <p>The symptom is worth describing because nothing about it says "CSP": the app boots, the Wasm
 * runs, the layout renders, every card and button is in the right place — and there is <b>no text
 * anywhere</b>. Every test in this repository passed against that page. So did
 * {@code verify:endpoints}, which asserts the headers are present and says nothing about whether
 * the page can be read.
 *
 * <p><b>Self-hosting the font would not remove the directive</b>, which is what settles it against
 * the renderer's precedent. Bundling Roboto stops the default-typeface fetch, but Flutter's font
 * fallback still reaches {@code fonts.gstatic.com} for glyphs the bundled fonts lack — a Noto Sans
 * Symbols fetch appeared in the same console log. So the choice is not "allow the host or bundle
 * the font", it is "allow the host, or accept that some glyphs render as tofu". Allowing it is
 * cheap in a way {@code script-src} never is: the host serves static files, an injected script can
 * push bytes into a URL against it but cannot read anything back, so it is not an exfiltration
 * channel — and it is one named host rather than a scheme or a wildcard.
 *
 * <h2>The one cross-origin host, and the one that was removed</h2>
 *
 * <p>Measured against the deployed service rather than a local {@code flutter run}, because a
 * policy tuned against a dev build passes every test and white-screens production. The real page
 * load fetched two things from outside its own origin:
 *
 * <ol>
 *   <li>{@code https://www.gstatic.com/flutter-canvaskit/<engine-rev>/skwasm.{js,wasm}} — the
 *       renderer, from Google's CDN. <strong>Removed rather than allow-listed.</strong> The build
 *       already stages a complete {@code canvaskit/} directory into the image and then ignored it;
 *       {@code --no-web-resources-cdn} makes the loader use the copy it is already shipping, so
 *       self-hosting costs nothing in bundle size and buys the strongest term in this policy —
 *       {@code script-src} stays {@code 'self'}. Allow-listing a CDN in {@code script-src} is
 *       permission to execute whatever that host serves, which is the one thing a CSP is for.
 *   <li>{@code https://fonts.gstatic.com/s/roboto/…woff2} — Roboto, fetched by the engine because
 *       it is the default typeface and is not bundled. <strong>Allow-listed.</strong> There is no
 *       build flag for this the way there is for the renderer; removing it means bundling a font
 *       and setting the theme's family in the application's UI, which is app-level work outside
 *       this module. Allowing it is cheap: a font is data, not code, and {@code font-src} grants no
 *       ability to execute anything. It is the term to delete once a font ships with the app.
 * </ol>
 *
 * <p>Everything else is closed. {@code frame-ancestors 'none'} (with the older
 * {@code X-Frame-Options} beside it for the same reason), {@code object-src 'none'},
 * {@code base-uri 'self'} so an injected {@code <base>} cannot re-point every relative URL on the
 * page, and {@code form-action 'self'}.
 */
@ApplicationScoped
public class SecurityHeaders {

  /**
   * One year. Long enough to be worth setting, and the maximum this deployment can honestly
   * promise — see {@link #strictTransportSecurity()} for why it stops short of the two additions
   * that usually accompany it.
   */
  static final String HSTS = "max-age=31536000";

  static final String CONTENT_SECURITY_POLICY =
      String.join(
          "; ",
          "default-src 'self'",
          "base-uri 'self'",
          "object-src 'none'",
          "frame-ancestors 'none'",
          "form-action 'self'",
          // WebAssembly compilation counts as script execution; the app does not start without it.
          "script-src 'self' 'wasm-unsafe-eval'",
          // Material UI and the Flutter engine both inject styles at runtime, with no nonce.
          "style-src 'self' 'unsafe-inline'",
          "img-src 'self' data: blob:",
          // The only third-party host in the policy, and it can only deliver a typeface. It has
          // to appear in BOTH of the next two directives — see the class javadoc, because which
          // one applies is not the one it looks like.
          "font-src 'self' https://fonts.gstatic.com",
          "connect-src 'self' https://fonts.gstatic.com",
          // The Wasm renderer rasterises on workers created from blob URLs.
          "worker-src 'self' blob:");

  void install(@Observes Router router) {
    router
        .route()
        .order(Integer.MIN_VALUE)
        .handler(
            rc -> {
              rc.addHeadersEndHandler(v -> apply(rc));
              rc.next();
            });
  }

  private void apply(RoutingContext rc) {
    var response = rc.response();
    response.putHeader("Content-Security-Policy", CONTENT_SECURITY_POLICY);
    // Redundant with frame-ancestors for anything current, and kept because "current" is not a
    // property of the browsers other people use.
    response.putHeader("X-Frame-Options", "DENY");
    // Stops a browser deciding for itself that a response is HTML or a script. The transport seam
    // negotiates content types deliberately (X-Zen-Transport); sniffing is the browser overruling
    // that, and it is how a stored value gets served back as script.
    response.putHeader("X-Content-Type-Options", "nosniff");
    // Full URL to this origin, bare origin to any other. Recovery and confirmation links carry
    // tokens in the URL (ADR-018), and the default policy would leak the path to third parties.
    response.putHeader("Referrer-Policy", "strict-origin-when-cross-origin");
    if (isHttps(rc)) {
      response.putHeader("Strict-Transport-Security", strictTransportSecurity());
    }
  }

  /**
   * {@code max-age} only: no {@code includeSubDomains}, no {@code preload}.
   *
   * <p>Cloud Run serves this application over HTTPS and nothing else, so the header costs nothing
   * and closes the first-request downgrade. The two usual additions are a different matter, and
   * both are refused for the same reason: they are promises about a hostname that is not settled.
   * The service answers on a {@code *.run.app} address today, and the domain question is open
   * (ADR-027 defers Cloudflare, and a domain arrives with it for App Links and mail).
   *
   * <p>{@code includeSubDomains} would bind names that do not exist yet and cannot be tested.
   * {@code preload} is worse: it is a submission to a list browser vendors ship, enforced by
   * software this repository does not control and unwound over months rather than by a deploy. A
   * one-way door is not something to walk through for a demo service on a generated hostname. Both
   * become correct once there is a real domain, and are cheap to add then.
   */
  static String strictTransportSecurity() {
    return HSTS;
  }

  /**
   * True when the browser reached this server over TLS.
   *
   * <p>Asked rather than assumed, because sending HSTS over plain HTTP is not merely useless — on
   * {@code localhost:8080} a browser that honoured it would pin the developer's machine to HTTPS
   * for a year, with no server there to answer. In production TLS terminates at Cloud Run's
   * frontend, so {@code isSSL()} is false on the connection Quarkus sees and the truth arrives in
   * {@code X-Forwarded-Proto}; {@code %prod} sets {@code proxy-address-forwarding}, which is what
   * makes {@code scheme()} report it. Both are checked so this is right in front of a proxy and
   * behind one.
   */
  private static boolean isHttps(RoutingContext rc) {
    return rc.request().isSSL() || "https".equalsIgnoreCase(rc.request().scheme());
  }
}
