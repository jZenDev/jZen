package zen.transport;

import jakarta.annotation.Priority;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import org.jboss.logging.Logger;
import zen.proto.v1.ZenError;

/**
 * The catch-all: any {@link Throwable} an application or framework code throws that no
 * type-specific mapper (e.g. {@code AuthExceptionMapper}, {@link InvalidBodyExceptionMapper})
 * claims first, lands here instead of falling through to Quarkus's default HTML/plain-text 500 —
 * which breaks the {@code ZenError} contract every client's {@code ZenClient} assumes on any
 * status >= 400, and can leak the exception's message and class name to the caller.
 *
 * <p>JAX-RS resolves an {@link ExceptionMapper} by walking the thrown exception's type hierarchy
 * for the <em>nearest</em> registered supertype, not by {@code @Priority} — so {@code
 * AuthException}/{@code InvalidProtocolBufferException} are already chosen over this one for any
 * exception that is (or extends) either, before this mapper is ever considered. The low priority
 * below is therefore a defensive, documented pin rather than the mechanism doing the real work: it
 * exists so that if a future mapper is ever registered at the same {@code Throwable} distance,
 * this one — the generic fallback — loses the tie rather than winning it by accident.
 *
 * <p>Always returns a <strong>fixed</strong> code and message, never {@code exception.getMessage()}
 * or the exception's class name: an unmapped exception is by definition one nobody has yet
 * decided is safe to describe to a caller. The full exception, with stack trace, is logged
 * server-side so the failure is still diagnosable.
 *
 * <p><strong>A {@link WebApplicationException} is passed through as its own response,
 * untouched.</strong> This is deliberate, not an oversight: Quarkus's own machinery throws these
 * for reasons that already carry the correct status — a {@code NotFoundException} for a request
 * past the static-resource handler's routing, for one, found the hard way when an earlier version
 * of this class rewrote that 404 into a 500. A {@code WebApplicationException} reaching here means
 * no more specific mapper claimed it, not that it is somehow less legitimate than one that did; its
 * own {@code Response} is the correct answer and this mapper's job is only to catch what escaped
 * with no answer at all.
 *
 * <p>Ships in {@code zen-transport} (Jandex-indexed), so every application inherits this the same
 * way it inherits the codecs and {@code InvalidBodyExceptionMapper}.
 */
@Provider
@Priority(ZenExceptionMapper.LOWEST_PRIORITY)
public class ZenExceptionMapper implements ExceptionMapper<Throwable> {

  /**
   * Deliberately far below {@code jakarta.ws.rs.Priorities.USER} (5000), the highest priority
   * value any hand-written provider in this codebase uses, so this mapper never outranks one on a
   * tie.
   */
  static final int LOWEST_PRIORITY = 10_000;

  private static final Logger LOG = Logger.getLogger(ZenExceptionMapper.class);

  @Override
  public Response toResponse(Throwable exception) {
    if (exception instanceof WebApplicationException wae && wae.getResponse() != null) {
      return wae.getResponse();
    }
    LOG.error("Unmapped exception reached the transport boundary", exception);
    ZenError error =
        ZenError.newBuilder()
            .setCode("internal_error")
            .setMessage("Something went wrong. Please try again.")
            .build();
    return Response.status(Response.Status.INTERNAL_SERVER_ERROR).entity(error).build();
  }
}
