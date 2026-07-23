package zen.identity.auth;

import zen.core.http.ZenStatus;
import zen.identity.IdentityMapper;
import zen.identity.IdentityService;
import zen.identity.user.User;
import zen.proto.v1.Identity;
import zen.proto.v1.LoginRequest;
import zen.proto.v1.RegisterRequest;
import zen.proto.v1.RestorePasswordRequest;
import io.quarkus.security.identity.SecurityIdentity;
import jakarta.annotation.security.PermitAll;
import jakarta.inject.Inject;
import jakarta.ws.rs.CookieParam;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.HttpHeaders;
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
 * The identity REST surface over Supabase, backing the client's {@code IdentityRepository}.
 *
 * <p>This is a framework resource: it lives in zen-identity (a Jandex-indexed library) so that
 * every jZen application inherits the auth surface just by depending on the module, instead of
 * re-declaring it. Quarkus discovers the resource from the jar via the Jandex index; the app
 * module runs SmallRye OpenAPI and supplies the referenced component schemas
 * ({@code Identity}, {@code LoginRequest}, ...) through its static {@code META-INF/openapi.yaml}.
 *
 * <p>Every proto-returning method returns {@link Response} wrapping the proto (a bare proto
 * return type triggers Quarkus's build-time Jackson writer and 500s) and declares its
 * OpenAPI schema by {@code $ref}. The wire format (JSON or Protobuf) is chosen by the
 * {@code zen.transport} seam from {@code X-Zen-Transport}; the method never names it.
 *
 * <p>One normally-named cookie per token: {@code zen_access_token} (SmallRye JWT reads it via
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
      responseCode = ZenStatus.OK,
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
      responseCode = ZenStatus.OK,
      description = "Registered; session cookies set when Supabase returns a session",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "Identity")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "Identity"))
      })
  public Response register(
      RegisterRequest request, @HeaderParam(HttpHeaders.ACCEPT_LANGUAGE) String acceptLanguage) {
    /*
     * Registration is the one moment the framework can learn a new user's language, so the header
     * seeds users.language - the column every later localized message (email above all) reads,
     * having no request of its own. It stays a header rather than a RegisterRequest field: the
     * locale is a property of the request, not of the identity being created, and keeping it out
     * of the proto leaves the wire contract untouched.
     */
    IdentityService.Session session =
        identityService.register(request.getEmail(), request.getPassword(), acceptLanguage);
    return sessionResponse(session);
  }

  @POST
  @Path("/restore-password")
  @PermitAll
  @Consumes({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Trigger the password-recovery email")
  @RequestBody(content = @Content(schema = @Schema(ref = "RestorePasswordRequest")))
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Recovery email dispatched if the address exists")
  public Response restorePassword(RestorePasswordRequest request) {
    identityService.restorePassword(request.getEmail());
    return Response.noContent().build();
  }

  @POST
  @Path("/logout")
  @PermitAll
  @Operation(summary = "Terminate the current session")
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Session cookies cleared")
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
      responseCode = ZenStatus.OK,
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
      responseCode = ZenStatus.OK,
      description = "The authenticated identity",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "Identity")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "Identity"))
      })
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "No active session")
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
