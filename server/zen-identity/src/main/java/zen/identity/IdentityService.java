package zen.identity;

import zen.identity.auth.PasswordRecoverRequest;
import zen.identity.auth.RedirectTargets;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.auth.SupabaseSessionResponse;
import zen.identity.auth.SupabaseSignupRequest;
import zen.identity.auth.SupabaseTokenRequest;
import zen.identity.auth.UserUpdateRequest;
import zen.identity.event.UserRegistered;
import zen.identity.security.RoleAugmentor;
import zen.identity.user.User;
import zen.identity.user.UserStore;
import io.quarkus.security.identity.SecurityIdentity;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Event;
import jakarta.inject.Inject;
import jakarta.ws.rs.WebApplicationException;
import java.util.UUID;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;

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

  private static final Logger LOG = Logger.getLogger(IdentityService.class);

  /**
   * GoTrue logout scope. {@code local} revokes the presented session only; {@code global} revokes
   * every session the user holds anywhere.
   *
   * <p>Local, because that is what a sign-out button means. A user ending a session on one device
   * does not expect their phone to be signed out too, and a framework that made every logout a
   * global one would be making a product decision on the application's behalf. "Sign out
   * everywhere" is a separate, deliberate action; when an application wants it, it passes
   * {@code global} — the seam is here for it.
   */
  private static final String LOGOUT_SCOPE_LOCAL = "local";

  private final SupabaseAuthClient authClient;
  private final UserStore userStore;
  private final Event<UserRegistered> registrations;
  private final RedirectTargets redirectTargets;

  /**
   * The caller's identity, for {@link #currentUser(UUID)} to read the row authentication already
   * loaded. A request-scoped proxy, so it is the current request's identity and nothing outlives
   * the request.
   */
  private final SecurityIdentity securityIdentity;

  @Inject
  public IdentityService(
      @RestClient SupabaseAuthClient authClient,
      UserStore userStore,
      Event<UserRegistered> registrations,
      RedirectTargets redirectTargets,
      SecurityIdentity securityIdentity) {
    this.authClient = authClient;
    this.userStore = userStore;
    this.registrations = registrations;
    this.redirectTargets = redirectTargets;
    this.securityIdentity = securityIdentity;
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
   * <p>{@code requestedRedirectUri} is where the confirmation link should return the user. It is
   * resolved through {@link RedirectTargets} before it goes anywhere near Supabase — blank means
   * the server's own default, and anything else must be a configured target. The check happens
   * first, so a rejected value never causes an email to be sent at all.
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
  public Session register(
      String email, String password, String preferredLanguage, String requestedRedirectUri) {
    String redirectUri = redirectTargets.resolve(requestedRedirectUri);
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

  /**
   * Triggers the Supabase recovery email. Best-effort; never leaks whether the email exists.
   *
   * <p>{@code requestedRedirectUri} is validated exactly as on registration, and for a sharper
   * reason: a recovery link can set a password, so a return address chosen by a stranger would be
   * an account takeover rather than merely a leak.
   */
  public void restorePassword(String email, String requestedRedirectUri) {
    String redirectUri = redirectTargets.resolve(requestedRedirectUri);
    call(
        () -> {
          authClient.recover(new PasswordRecoverRequest(email), redirectUri);
          return null;
        });
  }

  /**
   * Turns the tokens a Supabase email link delivered — confirmation, recovery, or invite — into a
   * jZen session, so that following the link lands the user signed in instead of back at a login
   * form. Supabase puts those tokens in the URL <em>fragment</em>, which never reaches a server, so
   * they can only arrive here by the client reading them and posting them back.
   *
   * <p>The access token is therefore an <b>untrusted input</b>, and is validated by presenting it
   * to Supabase ({@code GET /user}) before a single cookie is issued. Supabase is the only party
   * that can say the token is genuine, unexpired, and not revoked; verifying the signature locally
   * would accept one it had already invalidated. The upsert then reconciles the local profile, so
   * a user confirming their email gets the same row login would have created.
   *
   * <p>No language is passed to the upsert, for the reason {@link #toSession} gives: this is not
   * the moment a user chooses a language, and it must not overwrite the one registration recorded.
   */
  public Session exchangeLinkTokens(String accessToken, String refreshToken) {
    if (accessToken == null || accessToken.isBlank()) {
      throw AuthException.unauthorized("This link is missing its sign-in token.");
    }
    SupabaseSessionResponse.UserPayload supabaseUser =
        call(() -> authClient.getUser(bearer(accessToken)));
    if (supabaseUser == null || supabaseUser.id() == null) {
      throw AuthException.unauthorized("This link has expired. Please request a new one.");
    }
    return new Session(accessToken, refreshToken, userStore.upsertOnLogin(supabaseUser, null).user());
  }

  /**
   * Sets a new password for the identity owning {@code accessToken} — the final step of password
   * recovery, and the only reason a recovery link needs to establish a session at all.
   *
   * <p>The token comes from the caller's own session cookie, which SmallRye JWT has already
   * verified, so unlike {@link #exchangeLinkTokens} this one is trusted on arrival. Password rules
   * are Supabase's: a rejected password comes back through {@link #classifySupabaseError} as
   * {@code weak_password}, and jZen does not restate the rule in a second place where the two
   * could drift apart.
   */
  public void setPassword(String accessToken, String password) {
    if (password == null || password.isBlank()) {
      throw new AuthException(400, "weak_password", "Please choose a stronger password.");
    }
    call(
        () -> {
          authClient.updateUser(bearer(accessToken), new UserUpdateRequest(password));
          return null;
        });
  }

  private static String bearer(String accessToken) {
    return "Bearer " + accessToken;
  }

  /**
   * Revokes the session upstream, so signing out actually ends it instead of only clearing
   * cookies.
   *
   * <p>Returns whether the revocation landed. <strong>A caller must clear its cookies either
   * way.</strong> The user pressed sign out; if Supabase is unreachable, the honest outcome is
   * "signed out here, still live upstream" — not "we could not sign you out". Failing the request
   * would leave the session cookie in place as well, which is strictly worse on every axis.
   *
   * <p>So the failure is neither fatal nor hidden: it is logged at WARN as the security-relevant
   * event it is, because for the rest of the refresh token's seven days that session can still be
   * resumed by anyone holding it. The log line names the user id and nothing else — no token, no
   * email — the identifier Wave 0 settled on for exactly this purpose.
   *
   * @param accessToken the raw access-token cookie; blank when the caller had no session, in which
   *     case there is nothing upstream to revoke and no call is made
   * @param userId the session's subject, for the log line only; null when it could not be resolved
   */
  public boolean logout(String accessToken, UUID userId) {
    if (accessToken == null || accessToken.isBlank()) {
      // Logging out without a session is not a failure and not an event: a client that has already
      // lost its cookie still calls this, and a stranger can call it at any time.
      return false;
    }
    try {
      authClient.logout(bearer(accessToken), LOGOUT_SCOPE_LOCAL);
      return true;
    } catch (WebApplicationException e) {
      /*
       * The provider refuses a token it will not accept with 401 or 403 - which spelling depends on
       * how it failed, and neither is a problem here: both mean the session is already gone, which
       * is the outcome logout wanted. Treating 403 as a failure logged a security warning on the
       * most ordinary path there is (it was observed doing exactly that against a live server).
       * Reachable as a race even now that an unauthenticated caller skips this call entirely: the
       * token can expire between the request being authenticated and this call going out.
       */
      int status = e.getResponse() == null ? -1 : e.getResponse().getStatus();
      if (status == 401 || status == 403) {
        return true;
      }
      LOG.warnf(
          e,
          "Upstream logout was refused for user %s (HTTP %d): local cookies are cleared, but the"
              + " refresh token stays valid until it expires",
          userId,
          status);
      return false;
    } catch (RuntimeException e) {
      // Timeout, open circuit breaker, DNS, TLS - Supabase is unreachable rather than refusing.
      LOG.warnf(
          e,
          "Upstream logout failed for user %s: local cookies are cleared, but the session is still"
              + " live upstream and can be resumed with the refresh token",
          userId);
      return false;
    }
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

  /**
   * The local profile for an already-authenticated user id, or {@code null} if none.
   *
   * <p>Authenticating the caller already read this row: {@link RoleAugmentor} loads it to resolve
   * the role, and attaches it to the identity. Reading it again here was a second round trip to the
   * database — identical SQL, same parameter, a second transaction and so a second persistence
   * context — for ~135 ms of nothing on every authenticated request. So the attached row is used
   * when it is the row being asked for.
   *
   * <p>The identity match is on the id, not merely on the attribute's presence: the framework
   * exposes this method by user id, and an id that is not the authenticated caller's must never be
   * answered with the caller's own row. The fallback is the plain load, which also covers every
   * path where no augmentation happened — a service identity, a caller whose profile did not exist
   * when the request began, or a failed load that was logged and skipped.
   */
  public User currentUser(UUID id) {
    if (id != null && securityIdentity.getAttribute(RoleAugmentor.LOADED_USER) instanceof User user
        && id.equals(user.id)) {
      return user;
    }
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
