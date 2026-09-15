package zen.transport;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertSame;

import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.core.Response;
import org.junit.jupiter.api.Test;
import zen.proto.v1.ZenError;

/**
 * Unit test for {@link ZenExceptionMapper}, same rationale as {@link
 * InvalidBodyExceptionMapperTest}: {@code toResponse} needs no container. The claim that this
 * mapper does not shadow a type-specific one (e.g. {@code AuthExceptionMapper}) is a container
 * behavior (JAX-RS's nearest-supertype resolution), not something this unit test can prove — that
 * is instead the standing job of every app-module test that already asserts a specific {@code
 * ZenError} code from an {@code AuthException}-throwing endpoint (see {@code AuthResourceTest}):
 * any of those would start failing with {@code "internal_error"} the moment this mapper ever won
 * a resolution it should not have.
 */
class ZenExceptionMapperTest {

  private final ZenExceptionMapper mapper = new ZenExceptionMapper();

  @Test
  void unmappedThrowable_mapsTo500NotAContainerDefaultPage() {
    Response response = mapper.toResponse(new IllegalStateException("boom"));
    assertEquals(500, response.getStatus());
  }

  @Test
  void responseCarriesAFixedZenErrorNeverTheExceptionMessage() {
    Response response = mapper.toResponse(new RuntimeException("some leaky internal detail"));
    assertInstanceOf(ZenError.class, response.getEntity());
    ZenError error = (ZenError) response.getEntity();
    assertEquals("internal_error", error.getCode());
    assertFalse(error.getMessage().contains("leaky internal detail"));
  }

  @Test
  void messageNamesNoExceptionClassName() {
    Response response = mapper.toResponse(new ArrayIndexOutOfBoundsException(3));
    ZenError error = (ZenError) response.getEntity();
    assertFalse(error.getMessage().toLowerCase().contains("arrayindexoutofbounds"));
  }

  @Test
  void aWebApplicationExceptionIsPassedThroughUntouched() {
    // The regression this guards against: an earlier version rewrote every WebApplicationException
    // into a generic 500, which turned a static-resource-handler NotFoundException's honest 404
    // into a 500 for the same request. Anything of this type already carries the correct response.
    NotFoundException notFound = new NotFoundException();
    Response response = mapper.toResponse(notFound);
    assertSame(notFound.getResponse(), response);
    assertEquals(404, response.getStatus());
  }
}
