package dev.zen.transport;

import com.google.protobuf.Message;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.Response;

/** Shared reflection helper for the proto body readers. */
final class ProtoBuilders {

  private ProtoBuilders() {}

  /**
   * Returns a fresh builder for a protobuf message class via its static
   * {@code newBuilder()} method. Every generated message has one.
   */
  static Message.Builder newBuilder(Class<?> type) {
    try {
      return (Message.Builder) type.getDeclaredMethod("newBuilder").invoke(null);
    } catch (ReflectiveOperationException e) {
      throw new WebApplicationException(
          "Not a readable protobuf message type: " + type.getName(),
          e,
          Response.Status.INTERNAL_SERVER_ERROR);
    }
  }
}
