package zen.demo;

import jakarta.enterprise.context.ApplicationScoped;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Bounds how many WebSocket connections are open at once.
 *
 * <p><strong>Why this needs its own counter.</strong> A WebSocket leaves JAX-RS behind the moment
 * the HTTP upgrade completes, so {@code zen-ratelimit}'s filter — which is a JAX-RS
 * {@code @Provider} — never sees the connection again. The limiter charges the <em>handshake</em>
 * and nothing after it. Without a ceiling, a caller who holds the handshake budget can accumulate
 * sockets indefinitely: each is a file descriptor, a Netty channel and a read buffer on a 256Mi
 * instance, and they are not counted against {@code --concurrency=200} either, because that counts
 * in-flight requests rather than open connections.
 *
 * <p><strong>In-process, and legitimately so.</strong> A connection is held by the instance that
 * accepted it, so a per-instance count is the only count that means anything — this is not the
 * kind of in-process state ADR-028 warns about, because there is nothing to share. Raising
 * {@code --max-instances} does raise the fleet-wide total to N times this ceiling, which is the
 * correct behaviour rather than a defect: each instance can afford its own share.
 *
 * <p>Lives in the application rather than in {@code zen-transport}, deliberately. Putting it in the
 * framework's HTTP module would drag {@code quarkus-websockets-next} into every jZen application,
 * including the ones that never open a socket. Promoting it is the right move when a second
 * application wants it — on evidence, per ADR-008's rule for the shared {@code Clock} producer
 * (promoted to {@code zen-transport} once a second consumer appeared, DECISIONS ADR-051).
 */
@ApplicationScoped
public class WebSocketConnections {

  /**
   * Concurrently open sockets permitted across this instance.
   *
   * <p>200 matches {@code --concurrency=200}: it is deliberately not larger than the request
   * concurrency the service is sized for, because a socket costs at least as much to hold as a
   * request does. zen_demo's own use is one socket per open app tab.
   */
  @ConfigProperty(name = "zen.demo.websocket.max-connections", defaultValue = "200")
  int maxConnections;

  /**
   * Per-address ceiling, well below {@link #maxConnections}. Without it, a single caller who
   * reaches the global cap first locks out the whole fleet: {@code --max-instances=1} means there
   * is exactly one instance and no other caller to fail over to. 20 leaves room for a legitimate
   * user with several tabs/devices while making the whole-instance takeover this closes require
   * an order of magnitude more sockets than any real client opens.
   */
  @ConfigProperty(name = "zen.demo.websocket.max-connections-per-address", defaultValue = "20")
  int maxConnectionsPerAddress;

  private final AtomicInteger open = new AtomicInteger();
  private final ConcurrentHashMap<String, AtomicInteger> openPerAddress = new ConcurrentHashMap<>();

  /**
   * Claims a slot for {@code remoteAddress}, or refuses — either because the instance is at its
   * global ceiling, or because this address alone is already at {@link #maxConnectionsPerAddress}.
   *
   * @return {@code true} when the connection may proceed; the caller must then call
   *     {@link #release(String)} with the same address exactly once when it closes
   */
  public boolean tryAcquire(String remoteAddress) {
    if (!tryAcquireGlobal()) {
      return false;
    }
    AtomicInteger perAddress = openPerAddress.computeIfAbsent(remoteAddress, a -> new AtomicInteger());
    // Compare-and-set rather than incrementAndGet-then-check: the latter admits a transient
    // overshoot under concurrent upgrades, which is exactly when the ceiling matters.
    int current;
    do {
      current = perAddress.get();
      if (current >= maxConnectionsPerAddress) {
        // Give back the global slot claimed above — the per-address counter was never
        // incremented for this attempt, so only the global side needs undoing.
        open.decrementAndGet();
        return false;
      }
    } while (!perAddress.compareAndSet(current, current + 1));
    return true;
  }

  /** Frees a slot claimed by {@link #tryAcquire(String)} for the same {@code remoteAddress}. */
  public void release(String remoteAddress) {
    open.decrementAndGet();
    // computeIfPresent removes the entry once it reaches zero, atomically for that key — without
    // it every distinct address ever seen would keep a counter forever, an unbounded map for the
    // lifetime of the instance.
    openPerAddress.computeIfPresent(
        remoteAddress, (address, counter) -> counter.decrementAndGet() <= 0 ? null : counter);
  }

  private boolean tryAcquireGlobal() {
    int current;
    do {
      current = open.get();
      if (current >= maxConnections) {
        return false;
      }
    } while (!open.compareAndSet(current, current + 1));
    return true;
  }

  /** How many sockets are open right now. */
  public int openConnections() {
    return open.get();
  }

  /** The configured ceiling, for the endpoint's log line and for tests. */
  public int maxConnections() {
    return maxConnections;
  }
}
