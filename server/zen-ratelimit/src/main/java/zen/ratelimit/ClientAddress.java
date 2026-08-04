package zen.ratelimit;

import java.util.ArrayList;
import java.util.List;

/**
 * Resolves the address a rate limit is counted against.
 *
 * <p><strong>This is the class that decides whether the limiter works at all.</strong> Resolve the
 * address wrongly and there are exactly two outcomes, both silent: read a spoofable header and
 * every attacker gets an unlimited supply of fresh identities, so the limiter blocks no one; read
 * one address for everybody and the whole internet shares a counter, so the limiter blocks
 * everyone. Neither shows up as an error.
 *
 * <h2>Why {@code X-Forwarded-For} cannot simply be trusted</h2>
 *
 * <p>Any client can send {@code X-Forwarded-For: 1.2.3.4}. A proxy does not replace that header, it
 * <em>appends</em> to it. So the header a server receives is a list whose <em>left</em> end is
 * whatever the caller invented and whose <em>right</em> end was written by infrastructure. Reading
 * the leftmost entry — which is the conventional "original client" reading, and what Vert.x's own
 * {@code quarkus.http.proxy.allow-x-forwarded} does — is therefore reading attacker input.
 *
 * <p>Cloud Run is itself a proxy, so jZen genuinely is behind one and the header genuinely does
 * carry the real client. The resolution is to count from the <em>right</em>, by however many hops
 * the deployment actually has:
 *
 * <pre>
 *   X-Forwarded-For: 9.9.9.9, 203.0.113.7
 *                    ^^^^^^^  ^^^^^^^^^^^
 *                    spoofed  appended by Google's frontend — the real peer
 *   hops = 1  ->  203.0.113.7        (correct)
 *   hops = 0  ->  header ignored entirely, socket peer used
 * </pre>
 *
 * <p>{@code hops} is the number of trailing entries written by proxies under the operator's
 * control. It defaults to <strong>0</strong>, meaning "there is no trusted proxy, so ignore this
 * header completely" — the safe default, and the correct one for {@code %dev}, {@code %test} and
 * any bare-metal run. {@code %prod} sets 1, because jZen serves Cloud Run directly with nothing in
 * front of it (ADR-027). <strong>Putting an edge (a CDN, a load balancer) in front changes this
 * number</strong>, and getting it wrong reopens the bypass; {@link RateLimitAddressGuard} refuses
 * to boot on the configurations that are provably inconsistent.
 *
 * <p>Pure static logic with no container behind it, so the dangerous inputs can be expressed
 * directly in {@code ClientAddressTest}. An assembled application only ever has the safe one.
 */
public final class ClientAddress {

  /** The de-facto standard forwarding header. Case-insensitive on the wire. */
  public static final String FORWARDED_FOR = "X-Forwarded-For";

  /**
   * The address used when nothing identifies the caller. Every such request shares one counter,
   * which is the fail-closed direction: an unidentifiable flood is throttled as one caller rather
   * than waved through as many.
   */
  public static final String UNKNOWN = "unknown";

  private ClientAddress() {}

  /**
   * Picks the address to count against.
   *
   * @param forwardedFor the raw {@code X-Forwarded-For} header, or {@code null} if absent
   * @param socketPeer the transport-level peer address, used when the header is not trusted
   * @param trustedHops how many trailing {@code X-Forwarded-For} entries were written by proxies
   *     the operator controls; {@code 0} means the header is not trusted at all
   * @return a non-empty address string, never {@code null}
   */
  public static String resolve(String forwardedFor, String socketPeer, int trustedHops) {
    if (trustedHops <= 0) {
      /* No trusted proxy: the header is caller-controlled input and is not evidence of anything.
       * Note this is also the correct branch when the header is absent-but-present-in-spirit —
       * a caller who sends one anyway gets no benefit from it. */
      return normalize(socketPeer);
    }
    List<String> hops = parse(forwardedFor);
    if (hops.isEmpty()) {
      /* Configured to sit behind a proxy, but the request carries no forwarding header. Either
       * the request bypassed the proxy or the proxy is not adding one; the socket peer is the
       * only fact available. */
      return normalize(socketPeer);
    }
    /* Count from the right. If the caller sent fewer entries than there are trusted hops the list
     * is entirely infrastructure-written, so the leftmost is still the furthest-out truthful one. */
    int index = Math.max(0, hops.size() - trustedHops);
    return normalize(hops.get(index));
  }

  /**
   * Splits an {@code X-Forwarded-For} value into its hops, dropping blanks.
   *
   * <p>A header may legitimately appear more than once, in which case the container joins the
   * values with {@code ", "} — the same separator used within one value, so a single comma split
   * handles both shapes.
   */
  static List<String> parse(String forwardedFor) {
    List<String> hops = new ArrayList<>();
    if (forwardedFor == null) {
      return hops;
    }
    for (String hop : forwardedFor.split(",")) {
      String trimmed = hop.trim();
      if (!trimmed.isEmpty()) {
        hops.add(trimmed);
      }
    }
    return hops;
  }

  /**
   * Reduces an address to the form counted against.
   *
   * <p>The port is stripped: a caller's source port changes on every connection, so leaving it on
   * would hand every request its own counter and defeat the limiter entirely. IPv6 literals are
   * left alone — {@code ::1} is colon-rich and has no port to strip unless it is bracketed.
   */
  static String normalize(String address) {
    if (address == null) {
      return UNKNOWN;
    }
    String value = address.trim();
    if (value.isEmpty()) {
      return UNKNOWN;
    }
    if (value.startsWith("[")) {
      // Bracketed IPv6, optionally with :port — "[::1]:54321".
      int close = value.indexOf(']');
      return close > 0 ? value.substring(1, close) : value;
    }
    int colon = value.indexOf(':');
    if (colon > 0 && value.indexOf(':', colon + 1) < 0) {
      // Exactly one colon: IPv4 with a port.
      return value.substring(0, colon);
    }
    return value;
  }
}
