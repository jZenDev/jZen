package zen.identity;

/**
 * A domain-level authentication failure. Carries a stable machine-readable {@code code} and
 * an HTTP status; {@code AuthExceptionMapper} (in {@code zen.identity.auth}) renders it as a
 * {@code ZenError} proto body in whichever transport format the caller negotiated.
 *
 * <p>This keeps the identity <em>service</em> free of JAX-RS {@code Response} building: it throws
 * a plain exception, and the mapper beside it owns the wire mapping. Both ship in this library
 * rather than in an application, so every jZen app inherits the auth surface by depending on it
 * (see docs/architecture/DECISIONS.md ADR-001).
 */
public class AuthException extends RuntimeException {

  private final int status;
  private final String code;

  public AuthException(int status, String code, String message) {
    super(message);
    this.status = status;
    this.code = code;
  }

  public int status() {
    return status;
  }

  public String code() {
    return code;
  }

  /** 401 for invalid credentials or a rejected/expired session. */
  public static AuthException unauthorized(String message) {
    return new AuthException(401, "unauthorized", message);
  }
}
