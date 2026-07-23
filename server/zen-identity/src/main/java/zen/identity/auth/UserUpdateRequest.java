package zen.identity.auth;

/** Request body for {@code PUT /user}. */
public record UserUpdateRequest(String password) {}
