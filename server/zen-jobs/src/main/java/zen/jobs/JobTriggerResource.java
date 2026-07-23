package zen.jobs;

import jakarta.annotation.security.PermitAll;
import jakarta.inject.Inject;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import zen.core.http.ZenStatus;
import zen.proto.v1.ZenError;

/**
 * The single entry point an external scheduler calls to make due work happen.
 *
 * <p>A framework resource, like {@code AuthResource} and {@code AdminUserResource}: it lives in a
 * Jandex-indexed library so every jZen application inherits the trigger by depending on the module
 * (ADR-001 pt.3). The application supplies the referenced component schemas through its static
 * {@code META-INF/openapi.yaml}, and returns {@link Response} wrapping the proto rather than the
 * proto itself, per TA-1.
 *
 * <p><strong>One endpoint, N jobs.</strong> There is deliberately no per-job route: one scheduler
 * entry means one container start per tick, which is what keeps the single-instance cost model in
 * STANDARDS intact.
 *
 * <p><strong>Authentication is the header secret, and nothing else.</strong> The method is
 * {@code @PermitAll} because the Supabase session this application otherwise runs on is the wrong
 * credential for a machine caller - and, more importantly, must not be a sufficient one. A signed-in
 * user, admin included, gets 401 here without the secret; {@code JobTriggerResourceTest} asserts
 * exactly that.
 */
@Path("/api/v1/jobs")
public class JobTriggerResource {

  private static final String PROTOBUF = "application/x-protobuf";

  /** {@code ZenError} code returned when the shared secret is missing or wrong. */
  private static final String ERROR_UNAUTHORIZED = "unauthorized";

  private static final String UNAUTHORIZED_MESSAGE = "Invalid or missing job trigger credential";

  @Inject JobTriggerAuthenticator authenticator;
  @Inject JobScheduler scheduler;

  @POST
  @Path("/trigger")
  @PermitAll
  @Produces({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Run every scheduled job that is currently due")
  @Parameter(
      name = JobTriggerAuthenticator.TOKEN_HEADER,
      description = "Shared secret identifying the external scheduler")
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "The tick result: what was due and what happened to it",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "JobTickResult")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "JobTickResult"))
      })
  @APIResponse(
      responseCode = ZenStatus.UNAUTHORIZED,
      description = "Missing or invalid trigger credential (ZenError)")
  public Response trigger(@HeaderParam(JobTriggerAuthenticator.TOKEN_HEADER) String token) {
    if (!authenticator.isAuthorized(token)) {
      return Response.status(Response.Status.UNAUTHORIZED)
          .entity(
              ZenError.newBuilder()
                  .setCode(ERROR_UNAUTHORIZED)
                  .setMessage(UNAUTHORIZED_MESSAGE)
                  .build())
          .build();
    }
    return Response.ok(scheduler.tick()).build();
  }
}
