package zen.transport;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;

import com.google.protobuf.InvalidProtocolBufferException;
import jakarta.ws.rs.core.Response;
import org.junit.jupiter.api.Test;
import zen.proto.v1.ZenError;

/**
 * Unit test for {@link InvalidBodyExceptionMapper} — not a {@code @QuarkusTest}, for the same
 * reason as {@code CorsCredentialsGuardTest}: {@code toResponse} is plain logic that needs no
 * container, and this is the control F8 says the framework should be able to prove about itself
 * without an assembled app.
 */
class InvalidBodyExceptionMapperTest {

  private final InvalidBodyExceptionMapper mapper = new InvalidBodyExceptionMapper();

  @Test
  void malformedBody_mapsTo400NotAnUnmapped500() {
    Response response =
        mapper.toResponse(new InvalidProtocolBufferException("While parsing a protocol message"));
    assertEquals(400, response.getStatus());
  }

  @Test
  void responseCarriesAZenError() {
    Response response = mapper.toResponse(new InvalidProtocolBufferException("boom"));
    assertInstanceOf(ZenError.class, response.getEntity());
    ZenError error = (ZenError) response.getEntity();
    assertFalse(error.getCode().isBlank());
  }

  @Test
  void messageNamesNoParserInternals() {
    // This is the exact %dev leak F7 found reaching a client:
    // "InvalidProtocolBufferException: java.io.EOFException: End of input at line 1 column 10
    // path $.email" — none of that vocabulary may survive into the mapped message.
    Response response =
        mapper.toResponse(
            new InvalidProtocolBufferException(
                "java.io.EOFException: End of input at line 1 column 10 path $.email"));
    ZenError error = (ZenError) response.getEntity();
    String message = error.getMessage().toLowerCase();
    assertFalse(message.contains("eofexception"));
    assertFalse(message.contains("$.email"));
    assertFalse(message.contains("invalidprotocolbufferexception"));
    assertFalse(message.contains("line 1 column"));
  }
}
