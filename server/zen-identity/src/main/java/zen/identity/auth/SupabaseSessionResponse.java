package zen.identity.auth;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.Map;

/**
 * Supabase GoTrue session payload. Outbound Supabase calls are plain JSON, not proto, so
 * these DTOs are Jackson-mapped (client-side {@code quarkus-rest-client-jackson} only).
 *
 * <p>GoTrue's {@code /signup} response is polymorphic. When the project auto-confirms email it
 * returns a <b>session</b> ({@code access_token} plus a nested {@code user}), exactly like
 * {@code /token}. When email confirmation is required it returns a <b>bare user</b> — the user
 * fields at the top level, and no session at all. {@link #effectiveUser()} unifies the two so the
 * caller does not branch on the shape; the absence of an {@code access_token} is what tells the
 * caller confirmation is still pending.
 */
public record SupabaseSessionResponse(
    @JsonProperty("access_token") String accessToken,
    @JsonProperty("refresh_token") String refreshToken,
    UserPayload user,
    String error,
    @JsonProperty("error_description") String errorDescription,
    // Top-level user fields, populated only by the bare-user signup response (email confirmation
    // required). Null on session-shaped responses, which nest the user under `user`.
    @JsonProperty("id") String id,
    @JsonProperty("email") String email,
    @JsonProperty("email_confirmed_at") String emailConfirmedAt,
    @JsonProperty("user_metadata") Map<String, Object> userMetadata) {

  /**
   * The user from whichever shape GoTrue returned: the nested {@code user} of a session response,
   * or a {@link UserPayload} rebuilt from the top-level fields of a bare-user (confirmation
   * pending) response. Null if the response carries neither.
   */
  public UserPayload effectiveUser() {
    if (user != null) {
      return user;
    }
    if (id != null) {
      return new UserPayload(id, email, null, emailConfirmedAt, userMetadata);
    }
    return null;
  }

  public record UserPayload(
      String id,
      String email,
      @JsonProperty("role") String role,
      @JsonProperty("email_confirmed_at") String emailConfirmedAt,
      @JsonProperty("user_metadata") Map<String, Object> userMetadata) {

    /** True once Supabase has confirmed the email — i.e. {@code email_confirmed_at} is set. */
    public boolean emailVerified() {
      return emailConfirmedAt != null && !emailConfirmedAt.isBlank();
    }
  }
}
