package zen.identity.auth;

/**
 * Thrown for a Supabase response carrying a 5xx status — the provider itself failed, as opposed
 * to a {@link jakarta.ws.rs.WebApplicationException} 4xx, which means the request was rejected.
 *
 * <p>The distinction matters for fault tolerance: every {@code SupabaseAuthClient} method's
 * {@code @CircuitBreaker}/{@code @Retry} treats {@code WebApplicationException} as a real client
 * error that must skip the breaker and abort retries. A 5xx is the opposite — a transient
 * provider outage that should trip the breaker and be retried — so it is mapped to this distinct
 * type by {@code SupabaseAuthClient}'s {@code @ClientExceptionMapper} rather than left as a
 * {@code WebApplicationException}, which fault tolerance would otherwise treat identically to a
 * 4xx.
 */
public class SupabaseUnavailableException extends RuntimeException {

  private final int status;

  public SupabaseUnavailableException(int status) {
    super("Supabase responded with HTTP " + status);
    this.status = status;
  }

  public int status() {
    return status;
  }
}
