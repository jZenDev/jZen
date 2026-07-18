package dev.zen.identity.auth;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.Map;

/**
 * Supabase GoTrue session payload. Outbound Supabase calls are plain JSON, not proto, so
 * these DTOs are Jackson-mapped (client-side {@code quarkus-rest-client-jackson} only).
 *
 * <p>Ported verbatim from ../BugEater/.../auth/SupabaseSessionResponse.java.
 */
public record SupabaseSessionResponse(
    @JsonProperty("access_token") String accessToken,
    @JsonProperty("refresh_token") String refreshToken,
    UserPayload user,
    String error,
    @JsonProperty("error_description") String errorDescription) {

  public record UserPayload(
      String id,
      String email,
      @JsonProperty("role") String role,
      @JsonProperty("user_metadata") Map<String, Object> userMetadata) {}
}
