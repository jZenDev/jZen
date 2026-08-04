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
 * <h2>Three things bound this socket, and none of them is the same thing</h2>
 *
 * <ol>
 *   <li><strong>The handshake is authenticated</strong> ({@code @Authenticated}, enforced during
 *       the HTTP upgrade). Before this, the socket was the one route into the application that
 *       needed no credential at all: an anonymous caller could open it, and the session cookie
 *       every other route requires was simply never consulted. The upgrade is an ordinary HTTP
 *       request carrying the ordinary {@code zen_access_token} cookie, so this costs a signed-in
 *       client nothing it was not already sending — a browser attaches the cookie itself, and on
 *       native {@code ZenWebSocket} takes it from the same jar the HTTP client uses.
 *   <li><strong>Frame and message size are capped</strong>, in application.properties.
 *       {@code quarkus.http.limits.max-body-size} does not apply to WebSocket frames, so that
 *       ceiling had to be set separately or one connection could hand the instance an unbounded
 *       buffer.
 *   <li><strong>Concurrent connections are capped</strong> ({@link WebSocketConnections}). The
 *       rate limiter is a JAX-RS filter and stops seeing the connection once the upgrade
 *       completes, so it charges the handshake and nothing after it; an open socket is a cost the
 *       limiter cannot express.
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
   * Marks a connection that successfully claimed a capacity slot.
   *
   * <p>Recorded on the connection rather than inferred in {@link #onClose}, because a refused
   * connection also fires a close: releasing a slot that was never claimed would drive the counter
   * below zero, which reads as free capacity and quietly removes the ceiling altogether.
   */
  private static final UserData.TypedKey<Boolean> SLOT_HELD =
      UserData.TypedKey.forBoolean("zen.demo.ws.slot-held");

  @Inject WebSocketConnections connections;

  @OnOpen
  public void onOpen(WebSocketConnection connection) {
    if (!connections.tryAcquire()) {
      LOG.warnf(
          "Refusing a WebSocket connection: %d of %d slots are already open on this instance",
          connections.openConnections(), connections.maxConnections());
      connection.close(new CloseReason(TRY_AGAIN_LATER, "server at connection capacity"));
      return;
    }
    connection.userData().put(SLOT_HELD, Boolean.TRUE);
  }

  @OnClose
  public void onClose(WebSocketConnection connection) {
    if (Boolean.TRUE.equals(connection.userData().get(SLOT_HELD))) {
      connections.release();
    }
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
