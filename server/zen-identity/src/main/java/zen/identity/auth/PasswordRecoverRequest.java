package zen.identity.auth;

/**
 * Request body for {@code POST /recover}. Ported from ../BugEater/.../auth/PasswordRecoverRequest.java
 * (outbound record; the donor's bean-validation annotations are dropped, see SupabaseTokenRequest).
 */
public record PasswordRecoverRequest(String email) {}
