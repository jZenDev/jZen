package zen.identity.security;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import org.junit.jupiter.api.Test;

/**
 * Guards the shape of {@link UserRoleLoader}'s table-existence latch.
 *
 * <p>Caching the {@code to_regclass} probe removes a database round trip from every authenticated
 * request, and there is exactly one way to get it wrong that no functional test would catch.
 * GraalVM initialises most classes at <em>image build time</em> and writes their static fields into
 * the image heap, so a {@code static boolean} latch would be frozen at whatever the build machine
 * answered — and the build machine has no database, so it answers "no table". Every container from
 * that image would then start with the latch permanently false, re-probing forever: the cache
 * silently does nothing, which is the same failure shape as a lost Jandex index.
 *
 * <p>The mirror mistake is as bad in the other direction. If the native build ever ran the probe
 * successfully (against a build-time Dev Services database, say) a static latch would ship as
 * permanently <em>true</em>, and the degraded path this guard exists for would be gone.
 *
 * <p>So the assertion is on the field's modifiers rather than on behaviour: instance state is
 * constructed in the running process and cannot be snapshotted, and {@code volatile} is what makes
 * a write-once flag safe to read from the many event-loop threads that serve requests. Neither
 * property is visible from calling the class, which is why it is asserted here.
 */
class UserRoleLoaderLatchTest {

  private static final String LATCH = "usersTableConfirmed";

  @Test
  void theLatchIsInstanceState_soANativeImageCannotBakeItIn() throws Exception {
    Field latch = UserRoleLoader.class.getDeclaredField(LATCH);
    assertFalse(
        Modifier.isStatic(latch.getModifiers()),
        "UserRoleLoader." + LATCH + " is static. GraalVM snapshots static fields into the native"
            + " image at build time, where there is no database — the cache would ship frozen and"
            + " silently stop being a cache. It must be instance state on the @ApplicationScoped"
            + " bean.");
  }

  @Test
  void theLatchIsVolatile_becauseEveryEventLoopThreadReadsIt() throws Exception {
    Field latch = UserRoleLoader.class.getDeclaredField(LATCH);
    assertTrue(
        Modifier.isVolatile(latch.getModifiers()),
        "UserRoleLoader." + LATCH + " is not volatile. Requests are served on many threads, and a"
            + " non-volatile write may never become visible to them — every one would keep probing"
            + " the database, which is the cost this field exists to remove.");
  }
}
