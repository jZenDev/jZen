package dev.zen.app.auth;

import dev.zen.identity.IdentityMapper;
import dev.zen.identity.IdentityService;
import dev.zen.identity.auth.SessionService;
import dev.zen.identity.user.User;
import dev.zen.proto.v1.Identity;
import dev.zen.proto.v1.LoginRequest;
import dev.zen.proto.v1.RegisterRequest;
import dev.zen.proto.v1.RestorePasswordRequest;
import io.quarkus.security.identity.SecurityIdentity;
import jakarta.annotation.security.PermitAll;
import jakarta.inject.Inject;
import jakarta.ws.rs.CookieParam;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.NewCookie;
import jakarta.ws.rs.core.Response;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;

/**
 * The identity REST surface, backing DartZen's {@code IdentityRepository} (TA-5) over Supabase.
 *
 * <p>This resource lives in zen-app, not zen-identity, on purpose: zen-app is the only
 * {@code quarkus}-packaged module and it owns the REST surface, SmallRye OpenAPI, and the
 * static {@code META-INF/openapi.yaml} merge (the {@code HealthResource} precedent).
 * zen-identity stays a pure library of auth beans, the {@code User} entity, and the mapper,
 * discovered from its jar via a Jandex index.
 *
 * <p>Every proto-returning method returns {@link Response} wrapping the proto (a bare proto
 * return type triggers Quarkus's build-time Jackson writer and 500s, TA-1) and declares its
 * OpenAPI schema by {@code $ref} into {@code META-INF/openapi.yaml}. The wire format (JSON or
 * Protobuf) is chosen by the {@code dev.zen.transport} seam from {@code X-Zen-Transport}; the
 * method never names it.
 *
 * <p>Cookies are the un-hacked TA-4 set: {@code zen_access_token} (SmallRye JWT reads it via
 * {@code mp.jwt.token.cookie}), {@code zen_refresh_token}, and a JS-readable {@code XSRF-TOKEN}.
 * No {@code __session}, no {@code access|refresh} packing.
 */
@Path("/api/v1/auth")
public class AuthResource {

  private static final String PROTOBUF = "application/x-protobuf";

  @Inject IdentityService identityService;
  @Inject SessionService sessionService;
  @Inject IdentityMapper identityMapper;
  @Inject SecurityIdentity securityIdentity;

  @POST
  @Path("/login")
  @PermitAll
  @Consumes({MediaType.APPLICATION_JSON, PROTOBUF})
  @Produces({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Authenticate with email and password")
  @RequestBody(content = @Content(schema = @Schema(ref = "LoginRequest")))
  @APIResponse(
      responseCode = "200",
      description = "Authenticated; session cookies set",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "Identity")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "Identity"))
      })
  public Response login(LoginRequest request) {
    IdentityService.Session session =
        identityService.login(request.getEmail(), request.getPassword());
    return sessionResponse(session);
  }

  @POST
  @Path("/register")
  @PermitAll
  @Consumes({MediaType.APPLICATION_JSON, PROTOBUF})
  @Produces({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Register a new identity with email and password")
  @RequestBody(content = @Content(schema = @Schema(ref = "RegisterRequest")))
  @APIResponse(
      responseCode = "200",
      description = "Registered; session cookies set when Supabase returns a session",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "Identity")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "Identity"))
      })
  public Response register(RegisterRequest request) {
    IdentityService.Session session =
        identityService.register(request.getEmail(), request.getPassword());
    return sessionResponse(session);
  }

  @POST
  @Path("/restore-password")
  @PermitAll
  @Consumes({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Trigger the password-recovery email")
  @RequestBody(content = @Content(schema = @Schema(ref = "RestorePasswordRequest")))
  @APIResponse(responseCode = "204", description = "Recovery email dispatched if the address exists")
  public Response restorePassword(RestorePasswordRequest request) {
    identityService.restorePassword(request.getEmail());
    return Response.noContent().build();
  }

  @POST
  @Path("/logout")
  @PermitAll
  @Operation(summary = "Terminate the current session")
  @APIResponse(responseCode = "204", description = "Session cookies cleared")
  public Response logout() {
    return Response.noContent()
        .cookie(
            sessionService.clearCookie(SessionService.ACCESS_COOKIE),
            sessionService.clearCookie(SessionService.REFRESH_COOKIE),
            sessionService.clearCookie(SessionService.CSRF_COOKIE))
        .build();
  }

  @POST
  @Path("/refresh")
  @PermitAll
  @Produces({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Exchange the refresh-token cookie for a fresh session")
  @APIResponse(
      responseCode = "200",
      description = "Refreshed; new session cookies set",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "Identity")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "Identity"))
      })
  public Response refresh(@CookieParam(SessionService.REFRESH_COOKIE) String refreshToken) {
    IdentityService.Session session = identityService.refresh(refreshToken);
    return sessionResponse(session);
  }

  @GET
  @Path("/identity")
  @PermitAll
  @Produces({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Return the current identity, or 204 when anonymous")
  @APIResponse(
      responseCode = "200",
      description = "The authenticated identity",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "Identity")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "Identity"))
      })
  @APIResponse(responseCode = "204", description = "No active session")
  public Response getCurrentIdentity() {
    if (securityIdentity.isAnonymous()) {
      return Response.noContent().build();
    }
    UUID userId;
    try {
      userId = UUID.fromString(securityIdentity.getPrincipal().getName());
    } catch (IllegalArgumentException e) {
      return Response.noContent().build();
    }
    User user = identityService.currentUser(userId);
    if (user == null) {
      return Response.noContent().build();
    }
    return Response.ok(identityMapper.toProto(user)).build();
  }

  /** Builds a 200 {@link Identity} response, attaching whatever session cookies are available. */
  private Response sessionResponse(IdentityService.Session session) {
    Identity identity = identityMapper.toProto(session.user());
    List<NewCookie> cookies = new ArrayList<>();
    if (session.accessToken() != null) {
      cookies.add(sessionService.accessCookie(session.accessToken()));
      cookies.add(sessionService.csrfCookie(sessionService.generateCsrfToken()));
    }
    if (session.refreshToken() != null) {
      cookies.add(sessionService.refreshCookie(session.refreshToken()));
    }
    return Response.ok(identity).cookie(cookies.toArray(new NewCookie[0])).build();
  }
}
