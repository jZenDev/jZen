package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.enterprise.inject.spi.BeanManager;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.Config;
import org.eclipse.microprofile.config.ConfigProvider;
import org.junit.jupiter.api.Test;
import zen.identity.schema.MigrateOnlyRunner;

/**
 * Proves the deploy's migration step exists in an assembled application.
 *
 * <p>{@link MigrateOnlyRunner} lives in {@code zen-identity}, so Quarkus instantiates it only while
 * that module carries {@code META-INF/jandex.idx} — which it does only while its pom still runs
 * {@code jandex-maven-plugin}. Drop the plugin and the class stays on the classpath, still compiles,
 * still imports, and is never made a bean: the migration job would boot, migrate nothing, and exit
 * <strong>0</strong>. {@code deploy:cloudrun} would read that success and deploy a revision over a
 * schema that was never migrated. There is no runtime symptom until the first query, which is
 * exactly why this has to be an assertion rather than a code review — the precedent is
 * {@code RateLimitWiringTest} (ADR-029).
 *
 * <p>The mode's <em>own</em> behaviour cannot be fully asserted in process: it ends with
 * {@code System.exit}, and the interesting cases need a database that is ahead of the image.
 * {@code task test:native} runs the real thing — the real native image, migrate-only against an
 * empty database, before the same image is started to serve.
 */
@QuarkusTest
class MigrateOnlyWiringTest {

  @Inject BeanManager beanManager;
  @Inject MigrateOnlyRunner runner;

  @Test
  void theMigrateOnlyRunnerIsAnActiveBeanInTheAssembledApp() {
    assertNotNull(
        beanManager.resolve(beanManager.getBeans(MigrateOnlyRunner.class)),
        "zen-identity's migrate-only runner was not discovered — check that the module still runs"
            + " jandex-maven-plugin, or the deploy's migration step does nothing and exits 0");
  }

  @Test
  void theModeIsOffUnlessTheDeployAsksForIt() {
    // The default matters more than it looks: on every serving boot this bean must observe startup
    // and do nothing at all. Only the migration job sets these, per invocation — if either were
    // ever pinned on in a profile, the service would migrate and terminate instead of serving.
    Config config = ConfigProvider.getConfig();
    assertFalse(
        config.getOptionalValue("zen.migrate-only", Boolean.class).orElse(false),
        "zen.migrate-only must be off unless the deploy's migration job sets it");
    assertFalse(
        config.getOptionalValue("zen.allow-schema-rollback", Boolean.class).orElse(false),
        "zen.allow-schema-rollback must be off unless a rollback deliberately overrides the gate");
  }

  @Test
  void migratingAnAlreadyMigratedSchemaSucceedsAndAppliesNothing() {
    // %test still migrates at boot (Dev Services gives every run a throwaway database), so the
    // schema here is current. Running the deploy's step against it must be a no-op that reports
    // success — the ordinary case on every deploy that ships no new migration.
    assertEquals(MigrateOnlyRunner.EXIT_OK, runner.migrate());
  }
}
