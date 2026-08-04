package zen.identity.auth;

import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.faulttolerance.CircuitBreaker;
import org.eclipse.microprofile.faulttolerance.Retry;
import org.eclipse.microprofile.faulttolerance.Timeout;
import org.eclipse.microprofile.rest.client.annotation.ClientHeaderParam;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

/**
 * Typed client for the Supabase Auth (GoTrue) REST API.
 *
 * <p>Two conventions this interface relies on:
 *
 * <ul>
 *   <li>The base {@code /auth/v1} path segment is dropped from the interface because
 *       {@code quarkus.rest-client.supabase-auth.url} already ends in {@code /auth/v1}
 *       (application.properties). Method paths are therefore relative: {@code /token},
 *       {@code /signup}, {@code /recover}, {@code /user}.
 *   <li>GoTrue requires the project {@code apikey} header on every call; it is supplied
 *       once here from {@code supabase.key} config rather than per call site.
 * </ul>
 *
 * <p>Each call carries {@code @CircuitBreaker}/{@code @Retry}/{@code @Timeout}: a Supabase
 * 4xx ({@link WebApplicationException}) skips the breaker and aborts retries (it is a real
 * client error, not a transient fault), while timeouts and 5xx trip the breaker.
 */
@RegisterRestClient(configKey = "supabase-auth")
@ClientHeaderParam(name = "apikey", value = "${supabase.key}")
public interface SupabaseAuthClient {

  /**
   * Exchanges credentials for a session. {@code grantType} is {@code "password"} for email
   * login and {@code "refresh_token"} for a silent refresh.
   */
  @POST
  @Path("/token")
  @Consumes(MediaType.APPLICATION_JSON)
  @Produces(MediaType.APPLICATION_JSON)
  @CircuitBreaker(requestVolumeThreshold = 10, failureRatio = 0.5, delay = 5000, skipOn = WebApplicationException.class)
  @Retry(maxRetries = 2, delay = 500, abortOn = WebApplicationException.class)
  @Timeout(2000)
  SupabaseSessionResponse token(@QueryParam("grant_type") String grantType, SupabaseTokenRequest request);

  /** Registers a new user. Depending on project settings the response may carry no session. */
  @POST
  @Path("/signup")
  @Consumes(MediaType.APPLICATION_JSON)
  @Produces(MediaType.APPLICATION_JSON)
  @CircuitBreaker(requestVolumeThreshold = 10, failureRatio = 0.5, delay = 5000, skipOn = WebApplicationException.class)
  @Retry(maxRetries = 2, delay = 500, abortOn = WebApplicationException.class)
  @Timeout(2000)
  SupabaseSessionResponse signup(SupabaseSignupRequest request, @QueryParam("redirect_to") String redirectTo);

  /** Sends the password-recovery email. */
  @POST
  @Path("/recover")
  @Consumes(MediaType.APPLICATION_JSON)
  @CircuitBreaker(requestVolumeThreshold = 10, failureRatio = 0.5, delay = 5000, skipOn = WebApplicationException.class)
  @Retry(maxRetries = 2, delay = 500, abortOn = WebApplicationException.class)
  @Timeout(2000)
  void recover(PasswordRecoverRequest request, @QueryParam("redirect_to") String redirectTo);

  /**
   * Returns the user a bearer token belongs to, and 401s if the token is not genuine, has
   * expired, or has been revoked. This is the *validation* step for a token jZen did not issue
   * itself — the one an email link handed to the browser. Only Supabase can answer it: a local
   * signature check would happily accept a token Supabase had already invalidated.
   */
  @GET
  @Path("/user")
  @Produces(MediaType.APPLICATION_JSON)
  @CircuitBreaker(requestVolumeThreshold = 10, failureRatio = 0.5, delay = 5000, skipOn = WebApplicationException.class)
  @Retry(maxRetries = 2, delay = 500, abortOn = WebApplicationException.class)
  @Timeout(2000)
  SupabaseSessionResponse.UserPayload getUser(@HeaderParam("Authorization") String bearer);

  /**
   * Revokes the session a bearer token belongs to, so the refresh token stops working
   * <em>upstream</em> rather than merely being forgotten by the browser.
   *
   * <p>Clearing cookies ends a session only on the device that asked. The refresh token behind it
   * lives seven days and rotates on use, so without this call a token lifted from a device — or a
   * session left open on someone else's machine — stays usable for the rest of that week no matter
   * how many times the owner presses sign out. Only Supabase can invalidate it.
   *
   * <p>{@code scope} is GoTrue's: {@code local} revokes the presented session alone,
   * {@code global} revokes every session the user has. jZen sends {@code local} — see
   * {@code IdentityService#logout} for why — and the parameter exists because the upstream API has
   * it, not because a second caller is planned.
   *
   * <p>Returns 204 with no body. A 401 (the token already expired or was already revoked) means
   * the session is gone, which is the outcome the caller wanted; {@code IdentityService} treats it
   * as such rather than as an error to propagate.
   */
  @POST
  @Path("/logout")
  @CircuitBreaker(requestVolumeThreshold = 10, failureRatio = 0.5, delay = 5000, skipOn = WebApplicationException.class)
  @Retry(maxRetries = 2, delay = 500, abortOn = WebApplicationException.class)
  @Timeout(2000)
  void logout(@HeaderParam("Authorization") String bearer, @QueryParam("scope") String scope);

  /** Updates the authenticated user (e.g. sets a new password) using their bearer token. */
  @PUT
  @Path("/user")
  @Consumes(MediaType.APPLICATION_JSON)
  @Produces(MediaType.APPLICATION_JSON)
  @CircuitBreaker(requestVolumeThreshold = 10, failureRatio = 0.5, delay = 5000, skipOn = WebApplicationException.class)
  @Retry(maxRetries = 2, delay = 500, abortOn = WebApplicationException.class)
  @Timeout(2000)
  void updateUser(@HeaderParam("Authorization") String bearer, UserUpdateRequest request);
}
