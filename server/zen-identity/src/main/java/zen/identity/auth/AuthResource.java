package zen.identity.auth;

import zen.core.http.ZenStatus;
import zen.identity.IdentityMapper;
import zen.identity.IdentityService;
import zen.identity.user.User;
import zen.proto.v1.Identity;
import zen.proto.v1.LoginRequest;
import zen.proto.v1.RegisterRequest;
import zen.proto.v1.RestorePasswordRequest;
import zen.proto.v1.SessionExchangeRequest;
import zen.proto.v1.SetPasswordRequest;
import io.quarkus.security.Authenticated;
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
      description = "Registered and signed in (Supabase auto-confirms); session cookies set",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "Identity")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "Identity"))
      })
  @APIResponse(
      responseCode = ZenStatus.ACCEPTED,
      description =
          "Registered, email confirmation required: account created, no session yet. The returned"
              + " Identity has email_verified=false; the caller shows a \"check your email\" state.",
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
        identityService.register(
            request.getEmail(),
            request.getPassword(),
            acceptLanguage,
            request.getRedirectUri());
    /*
     * Whether registration also signs the user in depends on the Supabase project's email settings.
     * Auto-confirm returns a session (access token) -> 200 with session cookies, like login. Email
     * confirmation required returns no session -> 202 Accepted with the identity (email_verified is
     * false) and NO cookies: the account exists, but the user must confirm via the Supabase email
     * and then log in. sessionResponse omits cookies for a null token, but the status must also say
     * "not signed in", which a 200 would not.
     */
    if (session.accessToken() == null) {
      return Response.status(Response.Status.ACCEPTED)
          .entity(identityMapper.toProto(session.user()))
          .build();
    }
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
    identityService.restorePassword(request.getEmail(), request.getRedirectUri());
    return Response.noContent().build();
  }

  @POST
  @Path("/session")
  @PermitAll
  @Consumes({MediaType.APPLICATION_JSON, PROTOBUF})
  @Produces({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Exchange the tokens from a Supabase email link for a cookie session")
  @RequestBody(content = @Content(schema = @Schema(ref = "SessionExchangeRequest")))
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "Link accepted; session cookies set",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "Identity")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "Identity"))
      })
  @APIResponse(responseCode = ZenStatus.UNAUTHORIZED, description = "The link is invalid or expired")
  public Response exchangeSession(SessionExchangeRequest request) {
    /*
     * PermitAll by necessity: the caller has no session yet - acquiring one is the point. The
     * endpoint is not therefore unguarded. The token it receives is validated against Supabase
     * before any cookie is issued (see IdentityService.exchangeLinkTokens), so possession of a
     * genuine, live Supabase token is the credential, exactly as possession of the right password
     * is on /login. What this endpoint deliberately does NOT do is hand the token back out: it goes
     * into an httpOnly cookie, so a link opened once leaves no token readable by page scripts.
     */
    IdentityService.Session session =
        identityService.exchangeLinkTokens(request.getAccessToken(), request.getRefreshToken());
    return sessionResponse(session);
  }

  @POST
  @Path("/password")
  @Authenticated
  @Consumes({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Set a new password for the current session")
  @RequestBody(content = @Content(schema = @Schema(ref = "SetPasswordRequest")))
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Password changed")
  @APIResponse(responseCode = ZenStatus.UNAUTHORIZED, description = "No active session")
  public Response setPassword(
      SetPasswordRequest request, @CookieParam(SessionService.ACCESS_COOKIE) String accessToken) {
    /*
     * @Authenticated is what proves the session: SmallRye JWT has verified the cookie's signature
     * and expiry before this method runs. The raw cookie is read again here only because Supabase
     * wants the original bearer token, which the parsed SecurityIdentity no longer carries.
     *
     * This is the endpoint password recovery finishes on. It is not recovery-specific, though -
     * an ordinary signed-in user changing their password uses the same call, which is why it takes
     * no recovery token and asks nothing about how the session was obtained.
     */
    identityService.setPassword(accessToken, request.getPassword());
    return Response.noContent().build();
  }

  @POST
  @Path("/logout")
  @PermitAll
  @Operation(summary = "Terminate the current session")
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Session cookies cleared")
  public Response logout(@CookieParam(SessionService.ACCESS_COOKIE) String accessToken) {
    /*
     * Revoke first, then clear - but never let the first decide whether the second happens.
     * Clearing cookies alone ends the session on this device only; the refresh token behind it
     * remains usable upstream for seven days, which is what made signing out on a borrowed machine
     * theatre. IdentityService.logout does the revocation and reports a failure rather than
     * throwing, so a user who presses sign out while Supabase is down still ends up signed out
     * here. The failure is logged there, not swallowed.
     *
     * @PermitAll rather than @Authenticated: a caller whose access token has already expired must
     * still be able to clear their cookies, and a request with no session at all is a no-op, not
     * a 401.
     */
    if (!securityIdentity.isAnonymous()) {
      /*
       * Only a session the server accepts is worth revoking. A caller whose cookie no longer
       * verifies is anonymous (SessionCookieAuthenticationMechanism), and the provider would refuse
       * the token anyway - so attempting it would spend an outbound call per request on a certain
       * failure, log a security warning for the most ordinary event there is, and hand anyone an
       * amplifier: one cheap request in, one upstream call out. The cookies below are cleared
       * either way, which is the whole of what such a caller needs.
       */
      identityService.logout(accessToken, currentUserId());
    }
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
    UUID userId = currentUserId();
    if (userId == null) {
      return Response.noContent().build();
    }
    User user = identityService.currentUser(userId);
    if (user == null) {
      return Response.noContent().build();
    }
    return Response.ok(identityMapper.toProto(user)).build();
  }

  /**
   * The authenticated subject's id, or null when the caller is anonymous or the principal is not a
   * Supabase user id. Null is an ordinary answer here, not an error: every caller of this is on a
   * route that permits anonymous access.
   */
  private UUID currentUserId() {
    if (securityIdentity.isAnonymous()) {
      return null;
    }
    try {
      return UUID.fromString(securityIdentity.getPrincipal().getName());
    } catch (IllegalArgumentException e) {
      return null;
    }
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
