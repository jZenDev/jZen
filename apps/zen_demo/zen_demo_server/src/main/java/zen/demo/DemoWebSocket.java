package zen.demo;

import com.google.protobuf.InvalidProtocolBufferException;
import zen.proto.v1.WebSocketMessage;
import io.quarkus.websockets.next.OnBinaryMessage;
import io.quarkus.websockets.next.WebSocket;

/**
 * The demo WebSocket echo endpoint: it receives a {@link WebSocketMessage} and echoes it back
 * with {@code type="echo"}, or replies {@code type="error"} on a decode failure.
 *
 * <p>Unlike the HTTP surface (which negotiates JSON vs Protobuf per request), the socket is
 * single-format: frames are binary Protobuf. zen_demo's {@code ZenWebSocket} is constructed with
 * {@code ZenTransportFormat.protobuf}, so both web and native clients send binary frames and this
 * handler stays simple. The dual transport-mode requirement is covered by {@code /api/v1/demo/ping}.
 */
@WebSocket(path = "/api/v1/demo/ws")
public class DemoWebSocket {

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
