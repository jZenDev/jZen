package zen.demo;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;
import zen.identity.event.UserAnonymised;

/**
 * Test-only stand-in for an application's cascade-cleanup observer (issue #63): records every
 * {@link UserAnonymised} this test run fires, so {@code UserRetentionTest} can assert the event
 * exists and carries the right id without a real second table to cascade into.
 */
@ApplicationScoped
public class AnonymisationRecorder {

  private final List<UUID> observed = new CopyOnWriteArrayList<>();

  void onUserAnonymised(@Observes UserAnonymised event) {
    observed.add(event.userId());
  }

  List<UUID> observed() {
    return observed;
  }

  void clear() {
    observed.clear();
  }
}
