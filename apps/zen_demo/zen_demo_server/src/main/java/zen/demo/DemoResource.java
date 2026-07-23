package zen.demo;

import zen.core.http.ZenStatus;
import zen.core.i18n.ZenLocales;
import zen.identity.AuthException;
import zen.identity.IdentityService;
import zen.identity.user.User;
import zen.proto.v1.DemoProfile;
import zen.proto.v1.Ping;
import zen.proto.v1.Terms;
import io.quarkus.qute.i18n.Localized;
import io.quarkus.security.identity.SecurityIdentity;
import jakarta.annotation.security.PermitAll;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;

/**
 * The reference app's demo REST surface (ROADMAP step 4): {@code /ping}, {@code /terms}, and
 * {@code /profile}. Auth itself is not redeclared here - it is reused from the framework's
 * {@code AuthResource}.
 *
 * <p>Same rules as {@link HealthResource}: every method returns {@link Response} wrapping a proto
 * message (a bare proto return type triggers Quarkus's build-time Jackson writer and 500s)
 * and declares its OpenAPI schema by {@code $ref} into {@code META-INF/openapi.yaml}. The
 * {@code zen.transport} seam picks JSON or Protobuf from {@code X-Zen-Transport}; the method
 * never names a wire format. This is what lets the demo prove a typed round-trip in both modes.
 */
@Path("/api/v1/demo")
public class DemoResource {

  private static final String PROTOBUF = "application/x-protobuf";
  private static final String MARKDOWN = "text/markdown";

  @Inject DemoMessages messages; // default (en) bundle
  @Inject @Localized("uk") DemoMessages messagesUk; // Ukrainian variant
  @Inject IdentityService identityService;
  @Inject SecurityIdentity securityIdentity;

  @GET
  @Path("/ping")
  @PermitAll
  @Produces({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Liveness probe returning a message localized from Accept-Language")
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "Server is alive; message localized to the request locale",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "Ping")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "Ping"))
      })
  public Response ping(@HeaderParam(HttpHeaders.ACCEPT_LANGUAGE) String acceptLanguage) {
    String locale = ZenLocales.fromAcceptLanguage(acceptLanguage);
    Ping ping =
        Ping.newBuilder()
            .setMessage(bundle(locale).pingMessage())
            .setTimestampMs(System.currentTimeMillis())
            .build();
    return Response.ok(ping).build();
  }

  /** Selects the localized message bundle for the resolved locale (English is the fallback). */
  private DemoMessages bundle(String locale) {
    return ZenLocales.UK.equals(locale) ? messagesUk : messages;
  }

  @GET
  @Path("/terms")
  @PermitAll
  @Produces({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Localized Markdown terms of service")
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "Terms content for the request locale",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "Terms")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "Terms"))
      })
  public Response terms(@HeaderParam(HttpHeaders.ACCEPT_LANGUAGE) String acceptLanguage) {
    String locale = ZenLocales.fromAcceptLanguage(acceptLanguage);
    Terms terms =
        Terms.newBuilder()
            .setContent(readTerms(locale))
            .setContentType(MARKDOWN)
            .build();
    return Response.ok(terms).build();
  }

  @GET
  @Path("/profile")
  @PermitAll
  @Produces({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "The authenticated user's demo profile")
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "The current user's profile",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "DemoProfile")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "DemoProfile"))
      })
  @APIResponse(responseCode = ZenStatus.UNAUTHORIZED, description = "No active session (ZenError)")
  public Response profile() {
    /*
     * Auth-gated: SmallRye JWT authenticates from the zen_access_token cookie (mp.jwt.token.cookie),
     * so reaching a non-anonymous identity here proves the session cookie made the round trip - the
     * exact login -> authenticated-call flow that fails off-web without zen_transport's native
     * cookie jar. When anonymous we throw the shared AuthException, which AuthExceptionMapper renders
     * as a ZenError; this is the demo's asserted error path.
     */
    if (securityIdentity.isAnonymous()) {
      throw AuthException.unauthorized("Authentication required to view the demo profile");
    }
    UUID userId;
    try {
      userId = UUID.fromString(securityIdentity.getPrincipal().getName());
    } catch (IllegalArgumentException e) {
      throw AuthException.unauthorized("Session principal is not a valid user id");
    }
    User user = identityService.currentUser(userId);
    if (user == null) {
      throw AuthException.unauthorized("No user record for the current session");
    }
    return Response.ok(toProfile(user)).build();
  }

  /** Hand-builds the demo profile proto from the user entity (the IdentityMapper.toProto pattern). */
  private DemoProfile toProfile(User user) {
    String displayName =
        user.displayName != null
            ? user.displayName
            : (user.nickname != null ? user.nickname : user.email);
    return DemoProfile.newBuilder()
        .setUserId(user.id.toString())
        .setDisplayName(displayName != null ? displayName : "")
        .setEmail(user.email != null ? user.email : "")
        .setBio("Demo profile for " + user.email + " (role: " + user.role + ")")
        .build();
  }

  private String readTerms(String locale) {
    String resource = "terms/terms_" + locale + ".md";
    try (InputStream in =
        Thread.currentThread().getContextClassLoader().getResourceAsStream(resource)) {
      if (in == null) {
        throw new IllegalStateException("Missing demo terms resource: " + resource);
      }
      return new String(in.readAllBytes(), StandardCharsets.UTF_8);
    } catch (IOException e) {
      throw new UncheckedIOException("Failed to load " + resource, e);
    }
  }
}
