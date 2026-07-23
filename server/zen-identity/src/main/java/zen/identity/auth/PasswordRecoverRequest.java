package zen.identity.auth;

/**
 * Request body for {@code POST /recover}. An outbound record; see SupabaseTokenRequest for why
 * these carry no bean-validation annotations.
 */
public record PasswordRecoverRequest(String email) {}
