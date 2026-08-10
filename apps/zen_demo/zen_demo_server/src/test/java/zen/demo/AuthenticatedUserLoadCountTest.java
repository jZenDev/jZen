package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.security.identity.AuthenticationRequestContext;
import io.quarkus.security.identity.SecurityIdentity;
import io.quarkus.security.runtime.QuarkusPrincipal;
import io.quarkus.security.runtime.QuarkusSecurityIdentity;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.security.TestIdentityAssociation;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;
import org.hibernate.SessionFactory;
import org.hibernate.stat.Statistics;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import zen.identity.security.RoleAugmentor;
import zen.identity.user.User;
import zen.identity.user.UserRole;
import zen.transport.ZenTransportFormat;

/**
 * Counts how many times an authenticated request reads the {@code users} row.
 *
 * <p>It used to read it twice — once in {@link RoleAugmentor} to resolve the role, once again in
 * the resource — in two {@code @Transactional} units, so two persistence contexts, so Hibernate's
 * first-level cache could not serve the second. Byte-identical SQL, same parameter, and against a
 * cross-region database a measured ~135 ms per authenticated request.
 *
 * <p><b>The assertion is the count, not the status code.</b> A test that checked the endpoint still
 * answered 200 would have passed against the unfixed code and against every future regression of
 * it; the duplicate read had no symptom other than latency. This is the reasoning ADR-031 gives for
 * asserting row counts in both directions, applied to queries.
 *
 * <h2>Why the identity is augmented by hand</h2>
 *
 * <p>Because {@code @TestSecurity} alone does not run the augmentor. Without an
 * {@code authMechanism} it installs the identity straight into {@link TestIdentityAssociation} and
 * the HTTP mechanism that would call {@code SecurityIdentityAugmentor}s is never reached — so
 * {@code @TestSecurity(augmentors = RoleAugmentor.class)} reads the same as this test but silently
 * counts one load whether the defect is present or not. Minting a real Supabase JWT is the only
 * other way to reach the production path, and it is not available here.
 *
 * <p>So the two halves are put together exactly as a request puts them together: the real
 * {@link RoleAugmentor} augments the identity, that identity is what the request carries, and the
 * real resource answers from it. What is asserted is the total number of times the row is read to
 * serve one request, which is the quantity that was wrong.
 */
@QuarkusTest
@TestProfile(AuthenticatedUserLoadCountTest.StatisticsProfile.class)
class AuthenticatedUserLoadCountTest {

  /** Hibernate counts nothing unless asked to, and asking is a build-time decision. */
  public static class StatisticsProfile implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of("quarkus.hibernate-orm.statistics", "true");
    }
  }

  private static final UUID USER_ID = UUID.fromString("5e5e5e5e-0000-0000-0000-00000000000f");

  /** Runs the augmentor's blocking work synchronously on the calling thread. */
  private static final AuthenticationRequestContext SYNC =
      supplier -> Uni.createFrom().item(supplier.get());

  @Inject RoleAugmentor roleAugmentor;
  @Inject TestIdentityAssociation testIdentityAssociation;
  @Inject SessionFactory sessionFactory;

  private Statistics statistics;

  @BeforeEach
  void seedUserAndResetCounters() {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              if (User.<User>findById(USER_ID) == null) {
                User user = new User();
                user.id = USER_ID;
                user.email = "load-count@example.com";
                user.role = UserRole.USER;
                user.language = "en";
                user.createdAt = OffsetDateTime.now();
                user.persist();
              }
            });
    statistics = sessionFactory.getStatistics();
    statistics.clear();
  }

  @AfterEach
  void clearIdentity() {
    testIdentityAssociation.setTestIdentity(null);
  }

  /** What authentication does on every request: resolve the role from the database. */
  private void authenticate() {
    SecurityIdentity base =
        QuarkusSecurityIdentity.builder().setPrincipal(new QuarkusPrincipal(USER_ID.toString())).build();
    testIdentityAssociation.setTestIdentity(roleAugmentor.augment(base, SYNC).await().indefinitely());
  }

  private long userLoads() {
    return statistics.getEntityStatistics(User.class.getName()).getLoadCount();
  }

  private static io.restassured.specification.RequestSpecification json() {
    return given().header(ZenTransportFormat.HEADER, ZenTransportFormat.JSON.wire());
  }

  @Test
  void identity_readsTheUsersRowOnce() {
    authenticate();
    json().when().get("/api/v1/auth/identity").then().statusCode(200);

    assertEquals(
        1,
        userLoads(),
        "authenticating already read this row; the resource must use it rather than issue the"
            + " identical query in a second transaction");
  }

  @Test
  void demoProfile_readsTheUsersRowOnce() {
    authenticate();
    json().when().get("/api/v1/demo/profile").then().statusCode(200);

    assertEquals(1, userLoads(), "the app module inherits the saving without knowing about it");
  }

  @Test
  void anonymousRequest_readsNothing() {
    // ADR-030's SessionCookieAuthenticationMechanism yields no identity, so the augmentor is never
    // reached and an anonymous caller costs zero database round trips. The audit closed that as
    // already correct; this is here so carrying the row forward cannot quietly undo it.
    json().when().get("/api/v1/auth/identity").then().statusCode(204);
    json().when().get("/api/v1/demo/profile").then().statusCode(401);

    assertEquals(0, userLoads(), "an anonymous request must not touch the users table");
  }

  @Test
  void theRowIsNotRememberedBetweenRequests() {
    // This is a shorter request, not a cache. The row is carried on the SecurityIdentity, which is
    // built per authentication and reachable only from the request it was built for — so a second
    // request authenticates again and reads the row again. If it ever stopped doing so, ADR-017's
    // revocation guarantee would be gone: a role revoked in the database would keep working.
    for (int i = 0; i < 2; i++) {
      authenticate();
      json().when().get("/api/v1/auth/identity").then().statusCode(200);
    }

    assertEquals(2, userLoads(), "two requests must cost two reads, or revocation stops working");
  }
}
