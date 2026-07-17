package dev.zen.transport;

import com.google.protobuf.Message;
import com.google.protobuf.util.JsonFormat;
import jakarta.annotation.Priority;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.MultivaluedMap;
import jakarta.ws.rs.ext.MessageBodyWriter;
import jakarta.ws.rs.ext.Provider;
import java.io.IOException;
import java.io.OutputStream;
import java.lang.annotation.Annotation;
import java.lang.reflect.Type;
import java.nio.charset.StandardCharsets;

/**
 * Serializes any protobuf {@link Message} as canonical proto3 JSON for
 * {@code application/json}.
 *
 * <p>This exists because stock Jackson serializes protobuf-generated classes into their
 * builder internals (see BLUEPRINT.md, TA-1). {@link JsonFormat} emits the proto3 JSON
 * mapping that Dart's protoc_plugin and openapi-typescript also produce, so all three
 * languages agree on the JSON shape.
 */
@Provider
@Produces(MediaType.APPLICATION_JSON)
// Priority 1 (highest) so this wins over the quarkus-rest-jackson writer, which also
// claims application/json and would otherwise serialize the proto's builder internals
// (the runtime half of BLUEPRINT.md TA-1). Safe to be greedy: isWriteable matches only
// protobuf Message types.
@Priority(1)
public class ProtoJsonMessageBodyWriter implements MessageBodyWriter<Message> {

  private static final JsonFormat.Printer PRINTER =
      JsonFormat.printer().omittingInsignificantWhitespace();

  @Override
  public boolean isWriteable(Class<?> type, Type genericType, Annotation[] annotations, MediaType mediaType) {
    return Message.class.isAssignableFrom(type);
  }

  @Override
  public void writeTo(
      Message message,
      Class<?> type,
      Type genericType,
      Annotation[] annotations,
      MediaType mediaType,
      MultivaluedMap<String, Object> httpHeaders,
      OutputStream entityStream)
      throws IOException, WebApplicationException {
    entityStream.write(PRINTER.print(message).getBytes(StandardCharsets.UTF_8));
  }
}
