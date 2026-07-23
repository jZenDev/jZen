package zen.identity.auth;

import jakarta.ws.rs.Consumes;
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
