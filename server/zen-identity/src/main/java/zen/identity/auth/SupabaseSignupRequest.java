package zen.identity.auth;

import java.util.Map;

/**
 * Request body for {@code POST /signup}. An outbound record; see SupabaseTokenRequest for why
 * these carry no bean-validation annotations.
 */
public record SupabaseSignupRequest(String email, String password, Map<String, Object> data) {}
