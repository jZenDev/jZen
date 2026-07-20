package zen.identity.auth;

import zen.identity.AuthException;
import zen.proto.v1.ZenError;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;

/**
 * Renders an {@link AuthException} as a {@code ZenError} proto body at the exception's HTTP
 * status. The transport module's writers ({@code zen.transport}) serialize the proto in
 * whichever format the caller negotiated, and the response filter echoes {@code X-Zen-Transport},
 * so the client decodes the error with the same codec it would a success (its {@code ZenClient}
 * parses a {@code ZenError} on any status >= 400). This is the shared error path: endpoints
 * return typed proto, errors return the shared {@code ZenError} proto, never an ad-hoc envelope.
 */
@Provider
public class AuthExceptionMapper implements ExceptionMapper<AuthException> {

  @Override
  public Response toResponse(AuthException exception) {
    ZenError error =
        ZenError.newBuilder()
            .setCode(exception.code())
            .setMessage(exception.getMessage() != null ? exception.getMessage() : "")
            .build();
    // No explicit media type: the negotiated Accept header (rewritten by the pre-matching
    // transport filter) selects the matching proto writer, so a protobuf-mode caller gets a
    // protobuf ZenError and a JSON caller gets proto3-JSON, each matching the echoed header.
    return Response.status(exception.status()).entity(error).build();
  }
}
