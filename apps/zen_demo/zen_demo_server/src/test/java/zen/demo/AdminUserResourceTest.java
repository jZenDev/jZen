package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.protobuf.util.JsonFormat;
import zen.identity.user.User;
import zen.identity.user.UserRole;
import zen.proto.v1.AdminUser;
import zen.proto.v1.ZenError;
import zen.transport.ZenTransportFormat;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.core.Response.Status;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Proves the framework's admin users surface (ROADMAP step 5): the {@code @RolesAllowed} gate, the
 * ra-data-simple-rest pagination (a bare JSON array body + a {@code Content-Range} header), the
 * single-record get/update round-trip, and the {@code ZenError} not-found path. The admin role is
 * minted with {@code @TestSecurity} (the RoleAugmentor -> users-table path is proven separately by
 * {@link RoleAugmentorTest}); Dev Services provisions Postgres and Flyway migrates.
 */
@QuarkusTest
class AdminUserResourceTest {

  private static final String CONTENT_RANGE = "Content-Range";
  private static final String ADMIN_ID = "11111111-1111-1111-1111-111111111111";

  private static final UUID ALICE = UUID.fromString("aaaaaaaa-0000-0000-0000-000000000001");
  private static final UUID BOB = UUID.fromString("bbbbbbbb-0000-0000-0000-000000000002");
  private static final UUID CAROL = UUID.fromString("cccccccc-0000-0000-0000-000000000003");

  /** Applies the JSON transport header the admin panel always sends. */
  private static io.restassured.specification.RequestSpecification json() {
    return given().header(ZenTransportFormat.HEADER, ZenTransportFormat.JSON.wire());
  }

  @BeforeEach
  void seed() {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User.deleteAll();
              OffsetDateTime now = OffsetDateTime.now();
              persist(ALICE, "alice@example.com", "Alice", UserRole.USER, now.minusDays(2), false);
              persist(BOB, "bob@example.com", "Bob", UserRole.ADMIN, now.minusDays(1), true);
              persist(CAROL, "carol@example.com", "Carol", UserRole.REVIEWER, now, false);
            });
  }

  private static void persist(
      UUID id, String email, String name, UserRole role, OffsetDateTime createdAt, boolean premium) {
    User user = new User();
    user.id = id;
    user.email = email;
    user.displayName = name;
    user.role = role;
    user.language = "en";
    user.createdAt = createdAt;
    user.isPremium = premium;
    user.persist();
  }

  @Test
  @TestSecurity(user = ADMIN_ID, roles = UserRole.Names.ADMIN)
  void list_returnsPageAndContentRange() {
    Response resp =
        json()
            .queryParam("range", "[0,1]")
            .queryParam("sort", "[\"email\",\"ASC\"]")
            .queryParam("filter", "{}")
            .when()
            .get("/api/v1/admin/users")
            .andReturn();

    assertEquals(Status.OK.getStatusCode(), resp.statusCode());
    // range [0,1] is inclusive -> a 2-row page; the total (3) travels in Content-Range.
    assertEquals("users 0-1/3", resp.getHeader(CONTENT_RANGE));
    List<String> emails = resp.jsonPath().getList("email");
    assertEquals(List.of("alice@example.com", "bob@example.com"), emails, "sorted asc by email");
  }

  @Test
  @TestSecurity(user = ADMIN_ID, roles = UserRole.Names.ADMIN)
  void list_filtersByRole() {
    Response resp =
        json()
            .queryParam("range", "[0,24]")
            .queryParam("filter", "{\"role\":\"admin\"}")
            .when()
            .get("/api/v1/admin/users")
            .andReturn();

    assertEquals(Status.OK.getStatusCode(), resp.statusCode());
    assertEquals("users 0-0/1", resp.getHeader(CONTENT_RANGE));
    assertEquals(List.of("bob@example.com"), resp.jsonPath().getList("email"));
  }

  @Test
  @TestSecurity(user = ADMIN_ID, roles = UserRole.Names.ADMIN)
  void get_returnsSingleUser() throws Exception {
    Response resp = json().when().get("/api/v1/admin/users/" + BOB).andReturn();

    assertEquals(Status.OK.getStatusCode(), resp.statusCode());
    AdminUser.Builder parsed = AdminUser.newBuilder();
    JsonFormat.parser().ignoringUnknownFields().merge(resp.getBody().asString(), parsed);
    assertEquals("bob@example.com", parsed.getEmail());
    assertEquals(UserRole.Names.ADMIN, parsed.getRole());
    assertTrue(parsed.getIsPremium());
  }

  @Test
  @TestSecurity(user = ADMIN_ID, roles = UserRole.Names.ADMIN)
  void get_missingUser_returnsZenError() throws Exception {
    Response resp = json().when().get("/api/v1/admin/users/" + UUID.randomUUID()).andReturn();

    assertEquals(Status.NOT_FOUND.getStatusCode(), resp.statusCode());
    ZenError.Builder error = ZenError.newBuilder();
    JsonFormat.parser().ignoringUnknownFields().merge(resp.getBody().asString(), error);
    assertEquals("not_found", error.getCode());
  }

  @Test
  @TestSecurity(user = ADMIN_ID, roles = UserRole.Names.ADMIN)
  void update_persistsEditableFields() throws Exception {
    AdminUser payload =
        AdminUser.newBuilder()
            .setId(ALICE.toString())
            .setEmail("alice@example.com")
            .setRole(UserRole.Names.ADMIN)
            .setDisplayName("Alice Updated")
            .setIsPremium(true)
            .build();

    Response resp =
        json()
            .header(HttpHeaders.CONTENT_TYPE, ZenTransportFormat.JSON.mediaType())
            .body(JsonFormat.printer().print(payload))
            .when()
            .put("/api/v1/admin/users/" + ALICE)
            .andReturn();

    assertEquals(Status.OK.getStatusCode(), resp.statusCode());
    AdminUser.Builder updated = AdminUser.newBuilder();
    JsonFormat.parser().ignoringUnknownFields().merge(resp.getBody().asString(), updated);
    assertEquals(UserRole.Names.ADMIN, updated.getRole());
    assertEquals("Alice Updated", updated.getDisplayName());

    // The change is persisted, not just echoed.
    User reloaded = QuarkusTransaction.requiringNew().call(() -> User.findById(ALICE));
    assertEquals(UserRole.ADMIN, reloaded.role);
    assertTrue(reloaded.isPremium);
  }

  @Test
  @TestSecurity(user = ADMIN_ID, roles = UserRole.Names.USER)
  void list_nonAdmin_forbidden() {
    json().when().get("/api/v1/admin/users").then().statusCode(Status.FORBIDDEN.getStatusCode());
  }

  @Test
  void list_anonymous_unauthorized() {
    json().when().get("/api/v1/admin/users").then().statusCode(Status.UNAUTHORIZED.getStatusCode());
  }
}
