package zen.identity.user;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

/**
 * Unit tests for the admin list's page-size bound.
 *
 * <p>The range is a client-supplied query parameter, so its width is an attacker-chosen number of
 * rows to materialise on a 256Mi container. The bound is the difference between a large page and an
 * out-of-memory kill, and the cases that matter — a range in the billions, an integer overflow at
 * the top of the range — cannot be driven through the REST layer without the very allocation the
 * bound exists to prevent. So they are asserted directly against the parser.
 */
class AdminUserRangeTest {

  /** Mirrors {@code AdminUserResource.MAX_PAGE_SIZE}; a change there must be a change here. */
  private static final int MAX_PAGE_SIZE = 1000;

  @Test
  void absentRange_isTheDefaultPage() throws Exception {
    assertEquals(0, AdminUserResource.parseRange(null)[0]);
    assertEquals(24, AdminUserResource.parseRange(null)[1]);
    assertEquals(24, AdminUserResource.parseRange("  ")[1]);
  }

  @Test
  void ordinaryRange_passesThroughUnchanged() throws Exception {
    int[] parsed = AdminUserResource.parseRange("[25,49]");
    assertEquals(25, parsed[0]);
    assertEquals(49, parsed[1]);
  }

  @Test
  void hugeRange_isClampedNotRejected() throws Exception {
    /* react-admin's export asks for a very wide range on purpose. A truthful partial page plus
     * Content-Range answers it; a 400 would just break the button. */
    int[] parsed = AdminUserResource.parseRange("[0,999999999]");
    assertEquals(0, parsed[0]);
    assertEquals(MAX_PAGE_SIZE - 1, parsed[1]);
  }

  @Test
  void clampIsRelativeToTheStart_soLaterPagesAreStillFullWidth() throws Exception {
    int[] parsed = AdminUserResource.parseRange("[5000,999999999]");
    assertEquals(5000, parsed[0]);
    assertEquals(5000 + MAX_PAGE_SIZE - 1, parsed[1]);
  }

  @Test
  void startNearIntegerMax_doesNotOverflowIntoAWiderPage() throws Exception {
    /* start + MAX_PAGE_SIZE - 1 overflows int here. In int arithmetic the ceiling would come out
     * negative, end > ceiling would be false, and the clamp would silently not apply — widening
     * the page instead of narrowing it. */
    int[] parsed = AdminUserResource.parseRange("[" + (Integer.MAX_VALUE - 10) + ",2147483647]");
    assertEquals(Integer.MAX_VALUE - 10, parsed[0]);
    assertEquals(Integer.MAX_VALUE, parsed[1]);
  }

  @Test
  void negativeStart_isFlooredAtZero() throws Exception {
    assertEquals(0, AdminUserResource.parseRange("[-10,5]")[0]);
  }

  @Test
  void invertedRange_collapsesToASingleRow() throws Exception {
    int[] parsed = AdminUserResource.parseRange("[50,10]");
    assertEquals(50, parsed[0]);
    assertEquals(50, parsed[1]);
  }
}
