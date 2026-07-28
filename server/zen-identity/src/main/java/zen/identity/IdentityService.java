package zen.identity;

import zen.identity.auth.PasswordRecoverRequest;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.auth.SupabaseSessionResponse;
import zen.identity.auth.SupabaseSignupRequest;
import zen.identity.auth.SupabaseTokenRequest;
import zen.identity.event.UserRegistered;
import zen.identity.user.User;
import zen.identity.user.UserStore;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Event;
import jakarta.inject.Inject;
import jakarta.ws.rs.WebApplicationException;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.rest.client.inject.RestClient;

/**
 * Orchestrates the identity flows over Supabase Auth: call Supabase, reconcile the local
 * {@code users} row,
 * hand the resulting session back to {@code AuthResource} to set cookies and map to proto.
 *
 * <p>The outbound Supabase call runs outside any DB transaction; the local upsert is a
 * separate transactional bean ({@link UserStore}) so a network call never holds a DB lock.
 */
@ApplicationScoped
public class IdentityService {

  private final SupabaseAuthClient authClient;
  private final UserStore userStore;
  private final Event<UserRegistered> registrations;
  private final String redirectUri;

  @Inject
  public IdentityService(
      @RestClient SupabaseAuthClient authClient,
      UserStore userStore,
      Event<UserRegistered> registrations,
      @ConfigProperty(name = "auth.redirect-uri") String redirectUri) {
    this.authClient = authClient;
    this.userStore = userStore;
    this.registrations = registrations;
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
   *
   * <p>{@code preferredLanguage} is the raw tag of the registering request; it seeds
   * {@code users.language}, which is from then on the only locale source the framework has for
   * this user outside a request (localized email).
   *
   * <p>A {@link UserRegistered} event is fired asynchronously once the profile row is committed -
   * {@link UserStore#upsertOnLogin} is a transactional bean, so its transaction has already closed
   * when it returns. Applications observe the event to greet the user; nothing they do there can
   * fail or delay this method.
   */
  public Session register(String email, String password, String preferredLanguage) {
    SupabaseSessionResponse response;
    try {
      response =
          authClient.signup(new SupabaseSignupRequest(email, password, null), redirectUri);
    } catch (WebApplicationException e) {
      AuthException classified = classifySupabaseError(e);
      /*
       * No user enumeration on registration: an email that already exists must be indistinguishable
       * from a brand-new one. Surfacing "an account with this email already exists" would confirm a
       * registered address to an attacker (an enumeration oracle) and can leak a real email to a
       * spammer. So instead of throwing email_taken, return the same no-session outcome a genuine
       * pending confirmation produces - AuthResource renders both as the identical 202 "check your
       * email" response. Supabase's own enumeration protection normally returns 200 here (making
       * this branch unreachable), so this is defense-in-depth for a project that has it turned off.
       */
      if ("email_taken".equals(classified.code())) {
        return new Session(null, null, null);
      }
      throw classified;
    }
    // GoTrue returns a session when the project auto-confirms, and a bare user (no session) when
    // email confirmation is required. effectiveUser() unifies both; the null-token case below is
    // what AuthResource turns into a "confirm your email" (202) response.
    SupabaseSessionResponse.UserPayload supabaseUser = response.effectiveUser();
    if (supabaseUser == null || supabaseUser.id() == null) {
      throw new AuthException(400, "registration_failed", "Registration did not return a user.");
    }
    UserStore.Upsert upsert = userStore.upsertOnLogin(supabaseUser, preferredLanguage);
    User user = upsert.user();
    if (upsert.created()) {
      registrations.fireAsync(new UserRegistered(user.id, user.email, user.language));
    }
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
    /*
     * No language preference is passed: login and refresh must never overwrite a profile's own
     * setting. The argument only seeds a row this call creates, which on these paths means an
     * identity that exists in Supabase but had no local profile yet - it gets the fallback locale
     * and can change it later.
     */
    User user = userStore.upsertOnLogin(response.user(), null).user();
    return new Session(response.accessToken(), response.refreshToken(), user);
  }

  /**
   * Runs a Supabase call and, on a 4xx, translates it into a domain {@link AuthException} with a
   * stable code and a <em>user-safe</em> message. Two things this must never do: name the provider
   * ("Supabase rejected the request." is an internal detail and a small information leak), and hand
   * a raw upstream message to the client. The client keys on the {@code code} to show localized
   * wording; the message here is only a safe fallback.
   */
  private <T> T call(java.util.function.Supplier<T> supabaseCall) {
    try {
      return supabaseCall.get();
    } catch (WebApplicationException e) {
      throw classifySupabaseError(e);
    }
  }

  private AuthException classifySupabaseError(WebApplicationException e) {
    String body = "";
    try {
      jakarta.ws.rs.core.Response resp = e.getResponse();
      if (resp != null && resp.hasEntity()) {
        body = resp.readEntity(String.class);
      }
    } catch (RuntimeException ignore) {
      // No readable body; fall through to the generic case.
    }
    String b = body == null ? "" : body.toLowerCase(java.util.Locale.ROOT);
    if (contains(b, "email_not_confirmed", "email not confirmed", "not confirmed")) {
      return new AuthException(401, "email_not_confirmed", "Your email is not confirmed yet.");
    }
    if (contains(b, "already registered", "user_already_exists", "email_exists")) {
      // register() intercepts this code and turns it into the neutral 202 outcome, so it never
      // reaches the client; login/refresh cannot produce it. The message is a safe fallback only.
      return new AuthException(409, "email_taken", "An account with this email already exists.");
    }
    if (contains(b, "weak_password", "password should", "password is too")) {
      return new AuthException(400, "weak_password", "Please choose a stronger password.");
    }
    if (contains(b, "email_address_invalid", "unable to validate email", "invalid format")) {
      return new AuthException(400, "invalid_email", "That email address looks invalid.");
    }
    if (contains(b, "over_email_send_rate_limit", "rate limit", "too many requests")) {
      return new AuthException(
          429, "rate_limited", "Too many attempts. Please wait a moment and try again.");
    }
    if (contains(b, "invalid_credentials", "invalid_grant", "invalid login")) {
      return new AuthException(401, "invalid_credentials", "Incorrect email or password.");
    }
    // Unknown 4xx: a safe, generic message. Never the upstream text.
    return new AuthException(401, "unauthorized", "We could not complete your request.");
  }

  private static boolean contains(String haystack, String... needles) {
    for (String n : needles) {
      if (haystack.contains(n)) {
        return true;
      }
    }
    return false;
  }
}
