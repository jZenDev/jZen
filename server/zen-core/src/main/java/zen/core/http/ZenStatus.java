package zen.core.http;

/**
 * HTTP status codes as compile-time {@code String} constants, for use as MicroProfile OpenAPI
 * annotation values (e.g. {@code @APIResponse(responseCode = ZenStatus.OK)}).
 *
 * <p>Why a hand-written holder of literals rather than a wrapper over Jakarta's
 * {@code jakarta.ws.rs.core.Response.Status}? A Java annotation element must be a <em>constant
 * expression</em> (JLS 15.29). {@code Response.Status.OK.getStatusCode()} is a method call, so
 * {@code String.valueOf(Response.Status.OK.getStatusCode())} does <em>not</em> compile as an
 * annotation value ("element value must be a constant expression"). The only annotation-legal
 * form is a {@code String} literal, so these are literals - centralized here and documented.
 *
 * <p><strong>Extendable.</strong> This is an interface so a jZen application can add its own codes
 * by extending it, and reference the framework codes and its own through one type:
 * <pre>{@code
 * public interface AppStatus extends ZenStatus {
 *   String PAYMENT_REQUIRED = "402";
 * }
 * // @APIResponse(responseCode = AppStatus.OK)              // inherited from ZenStatus
 * // @APIResponse(responseCode = AppStatus.PAYMENT_REQUIRED)// the app's own
 * }</pre>
 * The inherited and added members are all implicitly {@code public static final String} and remain
 * compile-time constants, so both work in annotations.
 *
 * <p><strong>Usage rule.</strong> <em>Reference</em> these constants ({@code ZenStatus.OK}) or
 * <em>{@code extends}</em> the interface to add more. Do <em>not</em> {@code implements} it - that is
 * the "constant interface antipattern" (Effective Java, Item 22), which leaks the constants into the
 * implementing type's exported API. This interface is a namespace of values, not a type to implement.
 */
public interface ZenStatus {

  /** 200 OK. */
  String OK = "200";

  /** 201 Created. */
  String CREATED = "201";

  /** 204 No Content. */
  String NO_CONTENT = "204";

  /** 400 Bad Request. */
  String BAD_REQUEST = "400";

  /** 401 Unauthorized. */
  String UNAUTHORIZED = "401";

  /** 403 Forbidden. */
  String FORBIDDEN = "403";

  /** 404 Not Found. */
  String NOT_FOUND = "404";

  /** 409 Conflict. */
  String CONFLICT = "409";

  /** 500 Internal Server Error. */
  String INTERNAL_SERVER_ERROR = "500";
}
