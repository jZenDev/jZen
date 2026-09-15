package zen.transport;

import com.google.protobuf.Message;
import com.google.protobuf.util.JsonFormat;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.MultivaluedMap;
import jakarta.ws.rs.ext.MessageBodyReader;
import jakarta.ws.rs.ext.Provider;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.lang.annotation.Annotation;
import java.lang.reflect.Type;
import java.nio.charset.StandardCharsets;

/**
 * Parses a proto3-JSON {@code application/json} body into a protobuf {@link Message}.
 *
 * <p>{@link JsonFormat.Parser#ignoringUnknownFields()} means a field present in the body but not
 * in the target message's schema is silently dropped rather than rejected. That is deliberate on
 * both counts it buys: forward-compatibility with a client sending fields a slightly older server
 * does not know yet, and a mass-assignment defence (OWASP API3) — a caller cannot smuggle in an
 * unexpected field and have it land somewhere a stricter parser would have bound it. The trade-off
 * is that a genuine drift between the wire schema and the message a caller thinks they are sending
 * is invisible here at runtime; only {@code task verify:contracts}, which fails the build on
 * generated-file drift, catches that — not this reader.
 */
@Provider
@Consumes(MediaType.APPLICATION_JSON)
public class ProtoJsonMessageBodyReader implements MessageBodyReader<Message> {

  private static final JsonFormat.Parser PARSER = JsonFormat.parser().ignoringUnknownFields();

  @Override
  public boolean isReadable(Class<?> type, Type genericType, Annotation[] annotations, MediaType mediaType) {
    return Message.class.isAssignableFrom(type);
  }

  @Override
  public Message readFrom(
      Class<Message> type,
      Type genericType,
      Annotation[] annotations,
      MediaType mediaType,
      MultivaluedMap<String, String> httpHeaders,
      InputStream entityStream)
      throws IOException, WebApplicationException {
    Message.Builder builder = ProtoBuilders.newBuilder(type);
    try (Reader reader = new InputStreamReader(entityStream, StandardCharsets.UTF_8)) {
      PARSER.merge(reader, builder);
    }
    return builder.build();
  }
}
