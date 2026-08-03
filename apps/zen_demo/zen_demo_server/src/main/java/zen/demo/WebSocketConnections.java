package zen.demo;

import jakarta.enterprise.context.ApplicationScoped;
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
 * application wants it — on evidence, per ADR-008's rule for {@code JobClock}.
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

  private final AtomicInteger open = new AtomicInteger();

  /**
   * Claims a slot, or refuses.
   *
   * @return {@code true} when the connection may proceed; the caller must then call
   *     {@link #release()} exactly once when it closes
   */
  public boolean tryAcquire() {
    // Compare-and-set rather than incrementAndGet-then-check: the latter admits a transient
    // overshoot under concurrent upgrades, which is exactly when the ceiling matters.
    int current;
    do {
      current = open.get();
      if (current >= maxConnections) {
        return false;
      }
    } while (!open.compareAndSet(current, current + 1));
    return true;
  }

  /** Frees a slot claimed by {@link #tryAcquire()}. */
  public void release() {
    open.decrementAndGet();
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
