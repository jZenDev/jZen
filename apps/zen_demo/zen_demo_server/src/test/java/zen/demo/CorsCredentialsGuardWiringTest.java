package zen.demo;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.enterprise.inject.spi.BeanManager;
import jakarta.inject.Inject;
import org.junit.jupiter.api.Test;
import zen.transport.CorsCredentialsGuard;

/**
 * Proves the CORS guard is actually discovered in an assembled application.
 *
 * <p>This is the half its unit test cannot cover, and it is the half that fails silently. {@link
 * CorsCredentialsGuard} lives in a framework library, so Quarkus only sees its {@code
 * @Observes StartupEvent} method if {@code zen-transport} carries {@code META-INF/jandex.idx}.
 * Without that index the class is present on the classpath, compiles, imports fine, and is simply
 * never instantiated — no error, no warning, and a green suite over a guard that does nothing. A
 * missing bean here is the whole failure, so resolving it from the container is the assertion.
 *
 * <p>The guard's <em>logic</em> is tested in {@code CorsCredentialsGuardTest} in the library, where
 * the dangerous origin lists can be expressed. An assembled application only ever has the safe one.
 */
@QuarkusTest
class CorsCredentialsGuardWiringTest {

  @Inject BeanManager beanManager;

  @Test
  void theGuardIsAnActiveBeanInTheAssembledApp() {
    assertNotNull(
        beanManager.resolve(beanManager.getBeans(CorsCredentialsGuard.class)),
        "zen-transport's CORS guard was not discovered — check that the module still runs"
            + " jandex-maven-plugin, or it observes startup for nobody");
  }
}
