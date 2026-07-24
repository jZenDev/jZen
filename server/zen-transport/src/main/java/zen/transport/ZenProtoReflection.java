package zen.transport;

import io.quarkus.runtime.annotations.RegisterForReflection;
import zen.proto.v1.AdminUser;
import zen.proto.v1.DemoProfile;
import zen.proto.v1.HealthStatus;
import zen.proto.v1.Identity;
import zen.proto.v1.JobRun;
import zen.proto.v1.JobTickResult;
import zen.proto.v1.LoginRequest;
import zen.proto.v1.PageRequest;
import zen.proto.v1.Ping;
import zen.proto.v1.RegisterRequest;
import zen.proto.v1.RestorePasswordRequest;
import zen.proto.v1.Terms;
import zen.proto.v1.WebSocketMessage;
import zen.proto.v1.ZenError;

/**
 * Makes every generated protobuf message reflectively reachable in a native image.
 *
 * <p><b>Why this is needed.</b> The canonical proto3 JSON path — {@code JsonFormat}, used by
 * {@link ProtoJsonMessageBodyWriter} — resolves field accessors <em>reflectively</em> through
 * protobuf's {@code GeneratedMessage$FieldAccessorTable}. Without registration, a native image
 * strips those methods and the first JSON response fails with {@code NoSuchMethodException:
 * zen.proto.v1.HealthStatus.getStatus()}. The binary path is untouched, because it uses generated
 * code rather than reflection — which is why a deployed service can serve {@code
 * X-Zen-Transport: protobuf} perfectly while every JSON response returns 500. JSON being the
 * default, and the format both frontends speak, that is the whole product surface for web.
 *
 * <p><b>Why Quarkus does not infer it.</b> Quarkus registers types it can see on a JAX-RS method
 * signature. jZen's resources return {@link jakarta.ws.rs.core.Response} with an
 * {@code @APIResponse} schema ref, deliberately: a bare proto return type makes SmallRye emit
 * 130+ garbage OpenAPI schemas (STANDARDS "OpenAPI and the REST surface"). That trade is still
 * right, but its cost is that no proto type ever appears in a signature for static analysis to
 * find. This class pays that cost explicitly rather than leaving it to be rediscovered in
 * production.
 *
 * <p><b>Why an explicit list rather than a generator.</b> Enumerating classes invites drift, and
 * the honest fix for drift here is the same one the contract chain uses everywhere else: a gate,
 * not cleverness. {@code task sync:contracts} fails if a message declared in {@code
 * proto/zen/v1/*.proto} is missing below, so adding a message to a {@code .proto} without
 * registering it cannot reach a native build. Writing a bespoke script to emit GraalVM metadata
 * would have traded a readable list for a generator nobody asked for — MANIFESTO allows
 * industry-standard generators only, and this annotation <em>is</em> the platform's mechanism.
 *
 * <p><b>Why not {@code quarkus-grpc}</b>, which does register proto classes: it is the extension
 * for <em>gRPC</em>, and jZen serves REST. There is not one {@code service} block in {@code
 * proto/zen/v1} — protobuf here is a payload format selected by {@code X-Zen-Transport}, not an
 * RPC framework. Adding it would install a gRPC server that serves nothing, for a side effect.
 *
 * <p>Nested {@code Builder} types are covered because {@code ignoreNested} defaults to false;
 * {@code JsonFormat} needs the builders for parsing as much as the messages for printing.
 *
 * <p>This class is never instantiated. It exists only to carry the annotation, which is why it
 * lives in {@code zen-transport} — the module that owns the codecs that need it, and one Quarkus
 * already indexes (STANDARDS "Backend multi-module rules"). {@code zen-proto} could not host it:
 * it is deliberately the dependency-free leaf and must not gain a Quarkus dependency.
 */
@RegisterForReflection(
    targets = {
      AdminUser.class,
      DemoProfile.class,
      HealthStatus.class,
      Identity.class,
      JobRun.class,
      JobTickResult.class,
      LoginRequest.class,
      PageRequest.class,
      Ping.class,
      RegisterRequest.class,
      RestorePasswordRequest.class,
      Terms.class,
      WebSocketMessage.class,
      ZenError.class,
    })
public final class ZenProtoReflection {

  private ZenProtoReflection() {}
}
