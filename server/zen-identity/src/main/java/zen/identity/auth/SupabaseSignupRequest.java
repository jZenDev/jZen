package zen.identity.auth;

import java.util.Map;

/**
 * Request body for {@code POST /signup}. Ported from ../BugEater/.../auth/SupabaseSignupRequest.java
 * (outbound record; the donor's bean-validation annotations are dropped, see SupabaseTokenRequest).
 */
public record SupabaseSignupRequest(String email, String password, Map<String, Object> data) {}
