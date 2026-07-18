package dev.zen.identity.auth;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Request body for {@code POST /token}, used for both password login and silent refresh.
 * Ported from ../BugEater/.../auth/SupabaseTokenRequest.java. The donor's bean-validation
 * annotations are dropped: this is an outbound record whose values jZen controls, and inbound
 * validation lives in the resource/service layer, not here.
 */
public record SupabaseTokenRequest(
    String email,
    String password,
    @JsonProperty("refresh_token") String refreshToken,
    @JsonProperty("auth_code") String authCode,
    @JsonProperty("redirect_to") String redirectTo,
    @JsonProperty("code_verifier") String codeVerifier) {

  public SupabaseTokenRequest(
      String email, String password, String refreshToken, String authCode, String redirectTo) {
    this(email, password, refreshToken, authCode, redirectTo, null);
  }
}
