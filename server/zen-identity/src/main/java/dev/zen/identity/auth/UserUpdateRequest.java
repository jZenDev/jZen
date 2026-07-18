package dev.zen.identity.auth;

/** Request body for {@code PUT /user}. Ported from ../BugEater/.../auth/UserUpdateRequest.java. */
public record UserUpdateRequest(String password) {}
