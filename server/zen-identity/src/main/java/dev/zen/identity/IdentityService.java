package dev.zen.identity;

import dev.zen.identity.auth.PasswordRecoverRequest;
import dev.zen.identity.auth.SupabaseAuthClient;
import dev.zen.identity.auth.SupabaseSessionResponse;
import dev.zen.identity.auth.SupabaseSignupRequest;
import dev.zen.identity.auth.SupabaseTokenRequest;
import dev.zen.identity.user.User;
import dev.zen.identity.user.UserStore;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.WebApplicationException;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.rest.client.inject.RestClient;

/**
 * Orchestrates the identity flows over Supabase Auth. A focused re-implementation of
 * ../BugEater/.../auth/AuthService.java (the donor is large and couples in the discarded
 * Qute {@code *PageResource} surface): call Supabase, reconcile the local {@code users} row,
 * hand the resulting session back to {@code AuthResource} to set cookies and map to proto.
 *
 * <p>The outbound Supabase call runs outside any DB transaction; the local upsert is a
 * separate transactional bean ({@link UserStore}) so a network call never holds a DB lock.
 */
@ApplicationScoped
public class IdentityService {

  private final SupabaseAuthClient authClient;
  private final UserStore userStore;
  private final String redirectUri;

  @Inject
  public IdentityService(
      @RestClient SupabaseAuthClient authClient,
      UserStore userStore,
      @ConfigProperty(name = "auth.redirect-uri") String redirectUri) {
    this.authClient = authClient;
    this.userStore = userStore;
    this.redirectUri = redirectUri;
  }

  /** The tokens plus the reconciled local user, returned from every session-issuing flow. */
  public record Session(String accessToken, String refreshToken, User user) {}

  /** Email/password login. Throws {@link AuthException} (401) on rejected credentials. */
  public Session login(String email, String password) {
    SupabaseSessionResponse response =
        call(() -> authClient.token("password", new SupabaseTokenRequest(email, password, null, null, null)));
    return toSession(response);
  }

  /**
   * Registration. Depending on Supabase email-confirmation settings the response may carry no
   * session; the local user row is still created so the profile exists once confirmed.
   */
  public Session register(String email, String password) {
    SupabaseSessionResponse response =
        call(() -> authClient.signup(new SupabaseSignupRequest(email, password, null), redirectUri));
    if (response.user() == null || response.user().id() == null) {
      throw new AuthException(400, "registration_failed", "Registration did not return a user.");
    }
    User user = userStore.upsertOnLogin(response.user());
    return new Session(response.accessToken(), response.refreshToken(), user);
  }

  /** Triggers the Supabase recovery email. Best-effort; never leaks whether the email exists. */
  public void restorePassword(String email) {
    call(
        () -> {
          authClient.recover(new PasswordRecoverRequest(email), redirectUri);
          return null;
        });
  }

  /** Silent refresh using the refresh-token cookie. Throws {@link AuthException} (401) if rejected. */
  public Session refresh(String refreshToken) {
    if (refreshToken == null || refreshToken.isBlank()) {
      throw AuthException.unauthorized("Missing refresh token.");
    }
    SupabaseSessionResponse response =
        call(() -> authClient.token("refresh_token", new SupabaseTokenRequest(null, null, refreshToken, null, null)));
    return toSession(response);
  }

  /** Loads the local profile for an already-authenticated user id, or {@code null} if none. */
  public User currentUser(UUID id) {
    return userStore.findById(id);
  }

  private Session toSession(SupabaseSessionResponse response) {
    if (response.accessToken() == null || response.error() != null || response.user() == null) {
      String detail = response.errorDescription() != null ? response.errorDescription() : "Invalid credentials.";
      throw AuthException.unauthorized(detail);
    }
    User user = userStore.upsertOnLogin(response.user());
    return new Session(response.accessToken(), response.refreshToken(), user);
  }

  /** Translates a Supabase 4xx (a real client error) into a 401 {@link AuthException}. */
  private <T> T call(java.util.function.Supplier<T> supabaseCall) {
    try {
      return supabaseCall.get();
    } catch (WebApplicationException e) {
      throw AuthException.unauthorized("Supabase rejected the request.");
    }
  }
}
