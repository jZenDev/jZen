package zen.demo;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.enterprise.inject.spi.BeanManager;
import jakarta.inject.Inject;
import org.junit.jupiter.api.Test;
import zen.transport.SecurityHeaders;

/**
 * Proves the security-header route is actually discovered in an assembled application.
 *
 * <p>The same half that fails silently everywhere else in this repository. {@link SecurityHeaders}
 * lives in {@code zen-transport} and installs itself by observing the Vert.x {@code Router}, so
 * Quarkus sees it only while that module carries {@code META-INF/jandex.idx} — which it does only
 * while its pom still runs {@code jandex-maven-plugin}. Drop the plugin and the class stays on the
 * classpath, still compiles, still imports, and is never instantiated: no error, no warning, a
 * green suite, and every response served with no Content-Security-Policy and no frame protection.
 *
 * <p>Headers are a particularly bad thing to lose this way, because their absence has no symptom
 * at all. A missing rate limiter eventually shows up as abuse; a missing CSP shows up as nothing
 * until it is the reason an injection became an account takeover.
 *
 * <p>What the headers actually say is {@code SecurityHeadersTest}. This is about existence.
 */
@QuarkusTest
class SecurityHeadersWiringTest {

  @Inject BeanManager beanManager;

  @Test
  void theSecurityHeaderRouteIsAnActiveBeanInTheAssembledApp() {
    assertNotNull(
        beanManager.resolve(beanManager.getBeans(SecurityHeaders.class)),
        "zen-transport's security headers were not discovered — check that the module still runs"
            + " jandex-maven-plugin, or every response ships bare and nothing says so");
  }
}
