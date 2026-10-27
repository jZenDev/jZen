package zen.identity.auth;

import com.fasterxml.jackson.annotation.JsonProperty;

/** Request body for GoTrue's one-time {@code POST /verify} email-link exchange. */
public record SupabaseVerifyRequest(
    @JsonProperty("token_hash") String tokenHash, String type) {}
