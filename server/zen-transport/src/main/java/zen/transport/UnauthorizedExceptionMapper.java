package zen.transport;

import io.quarkus.security.UnauthorizedException;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import zen.proto.v1.ZenError;

/**
 * Renders a plain {@code @Authenticated}/{@code @RolesAllowed} rejection ({@link
 * UnauthorizedException}, thrown by Quarkus's own security interceptor before a resource method
 * runs) as a {@code ZenError} at 401, instead of letting it fall through to {@link
 * ZenExceptionMapper}'s generic 500. The interceptor's own exception carries no domain code the
 * way {@code zen.identity.AuthException} does, so it needed a mapper of its own the moment the
 * first resource stopped hand-rolling its own {@code securityIdentity.isAnonymous()} check and
 * started relying on the annotation alone (2026-09 code review, F23).
 *
 * <p>Ships in {@code zen-transport} rather than {@code zen-identity} because {@code @Authenticated}
 * is a plain Quarkus-security annotation any resource in any application can reach for, not
 * something specific to the Supabase-backed identity flows; every application already inherits
 * this module for the codecs, so it inherits this the same way.
 */
@Provider
public class UnauthorizedExceptionMapper implements ExceptionMapper<UnauthorizedException> {

  @Override
  public Response toResponse(UnauthorizedException exception) {
    ZenError error =
        ZenError.newBuilder().setCode("unauthorized").setMessage("Authentication required.").build();
    return Response.status(Response.Status.UNAUTHORIZED).entity(error).build();
  }
}
