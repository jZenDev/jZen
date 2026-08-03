package zen.demo;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.enterprise.inject.spi.BeanManager;
import jakarta.inject.Inject;
import org.junit.jupiter.api.Test;
import zen.jobs.ZenJob;
import zen.ratelimit.BurstLimiter;
import zen.ratelimit.DurableLimiter;
import zen.ratelimit.RateLimitAddressGuard;
import zen.ratelimit.RateLimitFilter;

/**
 * Proves the abuse layer is actually discovered in an assembled application.
 *
 * <p>This is the half a library unit test cannot cover, and it is the half that fails silently.
 * Every class asserted here lives in {@code zen-ratelimit}, so Quarkus sees it only if that module
 * carries {@code META-INF/jandex.idx} — which it does only while its pom still runs
 * {@code jandex-maven-plugin}. Drop that plugin and the classes stay on the classpath, still
 * compile, still import, and are never instantiated: no error, no warning, a green suite, and a
 * rate limiter that permits every request ever made. There is no runtime symptom to notice, which
 * is exactly why the check has to be an assertion rather than a code review.
 *
 * <p>The limiters' <em>logic</em> is tested in the library ({@code BurstLimiterTest},
 * {@code ClientAddressTest}, {@code RateLimitAddressGuardTest}), where the dangerous
 * configurations can be expressed. Its <em>enforcement</em> end to end is
 * {@code RateLimitEnforcementTest}. This test is about existence, and nothing else.
 */
@QuarkusTest
class RateLimitWiringTest {

  @Inject BeanManager beanManager;

  @Test
  void theRateLimitFilterIsAnActiveProviderInTheAssembledApp() {
    assertNotNull(
        beanManager.resolve(beanManager.getBeans(RateLimitFilter.class)),
        "zen-ratelimit's JAX-RS filter was not discovered — check that the module still runs"
            + " jandex-maven-plugin, or nothing is rate limited and nothing says so");
  }

  @Test
  void bothTiersAreActiveBeans() {
    assertNotNull(beanManager.resolve(beanManager.getBeans(BurstLimiter.class)), "burst tier");
    assertNotNull(beanManager.resolve(beanManager.getBeans(DurableLimiter.class)), "durable tier");
  }

  @Test
  void theAddressGuardIsAnActiveBean() {
    // It only ever runs at startup, so an undiscovered guard is indistinguishable from a guard
    // that passed — the worst shape a security check can have.
    assertNotNull(beanManager.resolve(beanManager.getBeans(RateLimitAddressGuard.class)));
  }

  @Test
  void theCounterCleanupJobIsRegisteredAsAZenJob() {
    // Registered as a ZenJob rather than @Scheduled, because with min-instances at 0 an
    // in-process cron has no thread alive at the hour it names. If this is not discovered, the
    // durable counter table grows without bound and nothing reports it.
    boolean registered =
        beanManager.getBeans(ZenJob.class).stream()
            .anyMatch(bean -> bean.getBeanClass().getName().contains("RateLimitCleanupJob"));
    assertTrue(registered, "the rate-limit counter cleanup job is not a registered ZenJob");
  }
}
