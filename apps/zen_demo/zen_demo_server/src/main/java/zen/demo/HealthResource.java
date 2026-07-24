package zen.demo;

import zen.core.http.ZenStatus;
import zen.proto.v1.HealthStatus;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;

/**
 * Walking-skeleton endpoint proving the dual-mode transport seam end to end.
 *
 * <p>The method returns the canonical domain model ({@link HealthStatus}, generated from
 * {@code proto/zen/v1/health.proto}) and never names a wire format. {@code zen.transport}
 * picks JSON or Protobuf from the {@code X-Zen-Transport} header. That is the "Zen"
 * developer experience the transport mandate asks for.
 *
 * <p>Two implementation notes, both required by STANDARDS "OpenAPI and the REST surface":
 * <ul>
 *   <li>The entity is wrapped in {@link Response} rather than returned as a bare
 *       {@code HealthStatus}. A bare proto return type triggers Quarkus REST's build-time
 *       Jackson writer, which serializes the proto's builder internals and 500s.
 *       {@code Response} forces runtime writer resolution, letting the priority-1 custom
 *       writers in {@code zen.transport} win.
 *   <li>The OpenAPI response is declared explicitly with a {@code $ref} to the
 *       {@code HealthStatus} schema supplied by {@code META-INF/openapi.yaml}. Without
 *       this, SmallRye introspects the proto class into 130+ garbage schemas.
 * </ul>
 */
@Path("/api/v1/health")
public class HealthResource {

  @GET
  @Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
  @Operation(summary = "Liveness/readiness probe")
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "Service is healthy",
      content = {
        @Content(
            mediaType = MediaType.APPLICATION_JSON,
            schema = @Schema(ref = "HealthStatus")),
        @Content(
            mediaType = "application/x-protobuf",
            schema = @Schema(ref = "HealthStatus"))
      })
  public Response health() {
    HealthStatus status =
        HealthStatus.newBuilder()
            .setStatus("ok")
            .setService("zen-demo-server")
            .setTimestampMs(System.currentTimeMillis())
            .build();
    return Response.ok(status).build();
  }
}
