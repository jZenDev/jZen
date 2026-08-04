package zen.ratelimit;

import jakarta.enterprise.context.ApplicationScoped;
import java.time.Duration;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * The configured {@link RateLimitConfig} — the values this deployment actually runs.
 *
 * <p>Plain {@code @ConfigProperty} fields rather than a {@code @ConfigMapping} interface, matching
 * how the rest of jZen's libraries read configuration. Every property is declared without a
 * {@code defaultValue}: the defaults live in this module's
 * {@code META-INF/microprofile-config.properties} instead, where they can be documented next to
 * the reasoning that produced each number, and where an application overrides one without
 * redeclaring the rest. A missing property is therefore a boot failure rather than a silently
 * substituted zero — which matters, because a rate limit that quietly becomes 0 either blocks
 * everything or, read the other way, nothing.
 *
 * <p>The keys are grouped {@code zen.ratelimit.<bucket>.<knob>} and read into one
 * {@link ConfiguredLimits} per bucket. See {@link RateLimitRule} for what each bucket covers.
 */
@ApplicationScoped
public class RateLimitProperties implements RateLimitConfig {

  @ConfigProperty(name = "zen.ratelimit.enabled")
  boolean enabled;

  @ConfigProperty(name = "zen.ratelimit.forwarded-hops")
  int forwardedHops;

  @ConfigProperty(name = "zen.ratelimit.counter-retention")
  Duration counterRetention;

  @ConfigProperty(name = "zen.ratelimit.max-tracked-subjects")
  int maxTrackedSubjects;

  @ConfigProperty(name = "zen.ratelimit.global.burst-limit")
  int globalBurstLimit;

  @ConfigProperty(name = "zen.ratelimit.global.burst-window")
  Duration globalBurstWindow;

  @ConfigProperty(name = "zen.ratelimit.global.durable-limit")
  int globalDurableLimit;

  @ConfigProperty(name = "zen.ratelimit.global.durable-window")
  Duration globalDurableWindow;

  @ConfigProperty(name = "zen.ratelimit.auth.burst-limit")
  int authBurstLimit;

  @ConfigProperty(name = "zen.ratelimit.auth.burst-window")
  Duration authBurstWindow;

  @ConfigProperty(name = "zen.ratelimit.auth.durable-limit")
  int authDurableLimit;

  @ConfigProperty(name = "zen.ratelimit.auth.durable-window")
  Duration authDurableWindow;

  @ConfigProperty(name = "zen.ratelimit.job-trigger.burst-limit")
  int jobTriggerBurstLimit;

  @ConfigProperty(name = "zen.ratelimit.job-trigger.burst-window")
  Duration jobTriggerBurstWindow;

  @ConfigProperty(name = "zen.ratelimit.job-trigger.durable-limit")
  int jobTriggerDurableLimit;

  @ConfigProperty(name = "zen.ratelimit.job-trigger.durable-window")
  Duration jobTriggerDurableWindow;

  @Override
  public boolean enabled() {
    return enabled;
  }

  @Override
  public int forwardedHops() {
    return forwardedHops;
  }

  @Override
  public Duration counterRetention() {
    return counterRetention;
  }

  @Override
  public int maxTrackedSubjects() {
    return maxTrackedSubjects;
  }

  @Override
  public Limits global() {
    return new ConfiguredLimits(
        globalBurstLimit, globalBurstWindow, globalDurableLimit, globalDurableWindow);
  }

  @Override
  public Limits auth() {
    return new ConfiguredLimits(
        authBurstLimit, authBurstWindow, authDurableLimit, authDurableWindow);
  }

  @Override
  public Limits jobTrigger() {
    return new ConfiguredLimits(
        jobTriggerBurstLimit,
        jobTriggerBurstWindow,
        jobTriggerDurableLimit,
        jobTriggerDurableWindow);
  }

  /** One bucket's four values, as read from configuration. */
  public record ConfiguredLimits(
      int burstLimit, Duration burstWindow, int durableLimit, Duration durableWindow)
      implements Limits {}
}
