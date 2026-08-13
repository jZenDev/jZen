package zen.demo;

import zen.core.http.ZenStatus;
import zen.proto.v1.HealthStatus;
import jakarta.annotation.security.PermitAll;
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
 *
 * <p>{@code @PermitAll} is required, not decorative: {@code zen-transport} ships
 * {@code quarkus.security.jaxrs.deny-unannotated-endpoints=true}, so an unannotated method is
 * denied rather than served (2026-08-13 architectural security review, F2). This endpoint is
 * meant to stay public — {@code gcloud run deploy} configures Cloud Run's startup/liveness probe
 * as a TCP check on the container port, not an HTTP call to this path, so nothing but a caller
 * checking liveness by hand depends on it being open, and that is exactly who {@code @PermitAll}
 * is for.
 */
@Path("/api/v1/health")
public class HealthResource {

  @GET
  @Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
  @PermitAll
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
