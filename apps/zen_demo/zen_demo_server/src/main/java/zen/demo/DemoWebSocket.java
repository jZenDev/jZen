package zen.demo;

import com.google.protobuf.InvalidProtocolBufferException;
import io.quarkus.security.Authenticated;
import io.quarkus.websockets.next.CloseReason;
import io.quarkus.websockets.next.OnBinaryMessage;
import io.quarkus.websockets.next.OnClose;
import io.quarkus.websockets.next.OnOpen;
import io.quarkus.websockets.next.UserData;
import io.quarkus.websockets.next.WebSocket;
import io.quarkus.websockets.next.WebSocketConnection;
import jakarta.inject.Inject;
import java.util.List;
import org.eclipse.microprofile.config.Config;
import org.jboss.logging.Logger;
import zen.proto.v1.WebSocketMessage;

/**
 * The demo WebSocket echo endpoint: it receives a {@link WebSocketMessage} and echoes it back with
 * {@code type="echo"}, or replies {@code type="error"} on a decode failure.
 *
 * <p>Unlike the HTTP surface (which negotiates JSON vs Protobuf per request), the socket is
 * single-format: frames are binary Protobuf. zen_demo's {@code ZenWebSocket} is constructed with
 * {@code ZenTransportFormat.protobuf}, so both web and native clients send binary frames and this
 * handler stays simple. The dual transport-mode requirement is covered by
 * {@code /api/v1/demo/ping}.
 *
 * <h2>Four things bound this socket, and none of them is the same thing</h2>
 *
 * <ol>
 *   <li><strong>The handshake is authenticated</strong> ({@code @Authenticated}, enforced during
 *       the HTTP upgrade). Before this, the socket was the one route into the application that
 *       needed no credential at all: an anonymous caller could open it, and the session cookie
 *       every other route requires was simply never consulted. The upgrade is an ordinary HTTP
 *       request carrying the ordinary {@code zen_access_token} cookie, so this costs a signed-in
 *       client nothing it was not already sending — a browser attaches the cookie itself, and on
 *       native {@code ZenWebSocket} takes it from the same jar the HTTP client uses.
 *   <li><strong>The handshake's {@code Origin} is checked against an explicit allowlist</strong>
 *       ({@code quarkus.http.cors.origins}, the same list the JAX-RS CORS filter already
 *       enforces). This is a WebSocket upgrade, not a fetch: CORS itself does not apply to it, and
 *       a browser will happily send the cookie cross-site because {@code SameSite=Lax} permits a
 *       top-level, cookie-bearing navigation-like request. The check states the defence outright
 *       rather than inheriting it from a cookie attribute that could change for an unrelated
 *       reason later. A request with no {@code Origin} header at all is let through: that is what
 *       a non-browser caller (jZen's own native {@code ZenWebSocket}) sends, and it carries none
 *       of the ambient-cookie risk a browser does.
 *   <li><strong>Frame and message size are capped</strong>, in application.properties.
 *       {@code quarkus.http.limits.max-body-size} does not apply to WebSocket frames, so that
 *       ceiling had to be set separately or one connection could hand the instance an unbounded
 *       buffer.
 *   <li><strong>Concurrent connections are capped, both globally and per address</strong>
 *       ({@link WebSocketConnections}). The rate limiter is a JAX-RS filter and stops seeing the
 *       connection once the upgrade completes, so it charges the handshake and nothing after it;
 *       an open socket is a cost the limiter cannot express. The per-address ceiling exists
 *       because {@code --max-instances=1} means there is exactly one instance: without it, a
 *       single caller reaching the global cap first locks out every other caller on the fleet.
 * </ol>
 */
@WebSocket(path = "/api/v1/demo/ws")
@Authenticated
public class DemoWebSocket {

  private static final Logger LOG = Logger.getLogger(DemoWebSocket.class);

  /**
   * WebSocket close code 1013, "Try Again Later" — the socket equivalent of a 429. Deliberately
   * not 1008 (policy violation), which would tell a well-behaved client it had done something
   * wrong and should stop, rather than that the server is full and it should come back.
   */
  private static final int TRY_AGAIN_LATER = 1013;

  /**
   * WebSocket close code 1008, "Policy Violation" — unlike {@link #TRY_AGAIN_LATER}, this
   * connection is refused on the merits and retrying from the same origin will not help.
   */
  private static final int POLICY_VIOLATION = 1008;

  /**
   * Marks a connection that successfully claimed a capacity slot, and the address it was claimed
   * for — {@link WebSocketConnections#release(String)} needs the same address {@link
   * WebSocketConnections#tryAcquire(String)} was called with.
   *
   * <p>Recorded on the connection rather than inferred in {@link #onClose}, because a refused
   * connection also fires a close: releasing a slot that was never claimed would drive the counter
   * below zero, which reads as free capacity and quietly removes the ceiling altogether.
   */
  private static final UserData.TypedKey<String> SLOT_HELD_FOR_ADDRESS =
      UserData.TypedKey.forString("zen.demo.ws.slot-held-for-address");

  private static final String ORIGINS_PROPERTY = "quarkus.http.cors.origins";

  @Inject WebSocketConnections connections;
  @Inject Config config;

  @OnOpen
  public void onOpen(WebSocketConnection connection) {
    String origin = connection.handshakeRequest().header("Origin");
    if (origin != null && !isAllowedOrigin(origin)) {
      LOG.warnf("Refusing a WebSocket handshake from a disallowed origin: %s", origin);
      connection.close(new CloseReason(POLICY_VIOLATION, "origin not allowed"));
      return;
    }
    String remoteAddress = connection.handshakeRequest().remoteAddress();
    if (!connections.tryAcquire(remoteAddress)) {
      LOG.warnf(
          "Refusing a WebSocket connection: %d of %d slots are already open on this instance",
          connections.openConnections(), connections.maxConnections());
      connection.close(new CloseReason(TRY_AGAIN_LATER, "server at connection capacity"));
      return;
    }
    connection.userData().put(SLOT_HELD_FOR_ADDRESS, remoteAddress);
  }

  @OnClose
  public void onClose(WebSocketConnection connection) {
    String heldForAddress = connection.userData().get(SLOT_HELD_FOR_ADDRESS);
    if (heldForAddress != null) {
      connections.release(heldForAddress);
    }
  }

  /**
   * Whether {@code origin} is one of the exact origins {@code quarkus.http.cors.origins}
   * configures — the same list the JAX-RS CORS filter enforces for the HTTP surface, read
   * directly from {@link Config} rather than injected as a field so a blank/unset property (which
   * CORS itself reads as "no restriction") is treated the same way here, matching the property's
   * actual semantics instead of quietly refusing every handshake because an empty list contains
   * nothing.
   */
  private boolean isAllowedOrigin(String origin) {
    List<String> allowed = config.getOptionalValues(ORIGINS_PROPERTY, String.class).orElse(List.of());
    return isAllowedOrigin(origin, allowed);
  }

  /** The matching rule alone, free of {@link Config}, so it can be unit-tested directly. */
  static boolean isAllowedOrigin(String origin, List<String> allowed) {
    return allowed.isEmpty() || allowed.contains("*") || allowed.contains(origin);
  }

  @OnBinaryMessage
  public byte[] onMessage(byte[] frame) {
    try {
      WebSocketMessage incoming = WebSocketMessage.parseFrom(frame);
      return WebSocketMessage.newBuilder()
          .setType("echo")
          .setPayload(incoming.getPayload())
          .build()
          .toByteArray();
    } catch (InvalidProtocolBufferException e) {
      return WebSocketMessage.newBuilder()
          .setType("error")
          .setPayload("ws_message_error")
          .build()
          .toByteArray();
    }
  }
}
