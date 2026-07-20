package zen.identity.user;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.protobuf.util.JsonFormat;
import zen.core.http.ZenStatus;
import zen.proto.v1.AdminUser;
import zen.proto.v1.ZenError;
import io.quarkus.hibernate.orm.panache.PanacheQuery;
import io.quarkus.panache.common.Sort;
import jakarta.annotation.security.RolesAllowed;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;

/**
 * The framework's admin management surface for the {@code users} table (ROADMAP step 5). Like
 * {@code AuthResource} this is a reusable JAX-RS resource served from a Jandex-indexed framework
 * library, so every jZen app's react-admin panel inherits user administration (the auth
 * precedent, ADR-001 pt.3 / ADR-005).
 *
 * <p>Gated to the {@code admin} role, which {@code RoleAugmentor} loads from the {@code users}
 * table into the {@code SecurityIdentity} (never from the JWT). The panel speaks JSON only
 * ({@code X-Zen-Transport: json}); the single-object endpoints still follow the TA-1 rule
 * ({@link Response} wrapping a proto + a {@code $ref} schema) so the transport seam serializes
 * them, while the list endpoint emits the {@code ra-data-simple-rest} convention: a bare JSON
 * array of {@link AdminUser} plus a {@code Content-Range} header carrying the total (ADR-005
 * chose the bare array over a wrapper proto). Each array element is still the declared
 * {@code AdminUser} proto, rendered via proto3 canonical JSON, so the contract stays first.
 */
@Path("/api/v1/admin/users")
@RolesAllowed(UserRole.Names.ADMIN)
public class AdminUserResource {

  private static final String PROTOBUF = "application/x-protobuf";
  private static final String RANGE_UNIT = "users";
  private static final String CONTENT_RANGE_HEADER = "Content-Range";
  /** Default page size when react-admin sends no range (its default perPage is also this). */
  private static final int DEFAULT_PAGE_SIZE = 25;
  /** Panache property the list falls back to when the sort field is absent or not whitelisted. */
  private static final String DEFAULT_SORT_PROPERTY = "createdAt";
  /** ra-data-simple-rest order token for a descending sort (the ascending token is anything else). */
  private static final String ORDER_DESCENDING = "DESC";
  /** ra-data-simple-rest filter keys this resource understands. */
  private static final String FILTER_ROLE = "role";
  private static final String FILTER_QUERY = "q";
  /** ZenError code for a missing record. */
  private static final String ERROR_NOT_FOUND = "not_found";

  private static final ObjectMapper JSON = new ObjectMapper();
  /**
   * proto3-JSON printer that keeps zero-valued fields, so every {@link AdminUser} in the list
   * array carries a stable key set (react-admin fields such as {@code isPremium}/{@code
   * lastLoginAtMs} must be present even when false/0).
   */
  private static final JsonFormat.Printer PRINTER =
      JsonFormat.printer().alwaysPrintFieldsWithNoPresence().omittingInsignificantWhitespace();

  /**
   * ra-data-simple-rest sort field (proto3-JSON camelCase) to Panache entity property. Only
   * whitelisted fields are sortable; anything else falls back to {@code createdAt desc}.
   */
  private static final Map<String, String> SORTABLE =
      Map.of(
          "id", "id",
          "email", "email",
          "displayName", "displayName",
          "nickname", "nickname",
          "role", "role",
          "language", "language",
          "isPremium", "isPremium",
          "createdAtMs", "createdAt",
          "lastLoginAtMs", "lastLoginAt");

  @GET
  @Produces(MediaType.APPLICATION_JSON)
  @Operation(summary = "List users for the admin panel (paginated via the Content-Range convention)")
  @Parameter(name = "range", description = "ra-data-simple-rest range, JSON [start,end] inclusive, e.g. [0,24]")
  @Parameter(name = "sort", description = "ra-data-simple-rest sort, JSON [field,order], e.g. [\"email\",\"ASC\"]")
  @Parameter(name = "filter", description = "ra-data-simple-rest filter, JSON object; supports role and q (email)")
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "A page of users; total row count in the Content-Range header",
      content = @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "AdminUserList")))
  @APIResponse(responseCode = ZenStatus.UNAUTHORIZED, description = "No active session")
  @APIResponse(responseCode = ZenStatus.FORBIDDEN, description = "Session lacks the admin role")
  @Transactional
  public Response list(
      @QueryParam("range") String range,
      @QueryParam("sort") String sort,
      @QueryParam("filter") String filter)
      throws Exception {
    int[] bounds = parseRange(range);
    int start = bounds[0];
    int end = bounds[1];

    PanacheQuery<User> query = User.find(buildFilter(filter), buildSort(sort), filterParams(filter));
    long total = query.count();
    List<User> page = query.range(start, end).list();

    StringBuilder json = new StringBuilder("[");
    for (int i = 0; i < page.size(); i++) {
      if (i > 0) {
        json.append(',');
      }
      json.append(PRINTER.print(toProto(page.get(i))));
    }
    json.append(']');

    int last = page.isEmpty() ? start : start + page.size() - 1;
    String contentRange = RANGE_UNIT + " " + start + "-" + last + "/" + total;
    return Response.ok(json.toString(), MediaType.APPLICATION_JSON)
        .header(CONTENT_RANGE_HEADER, contentRange)
        .build();
  }

  @GET
  @Path("/{id}")
  @Produces({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Get a single user by id")
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "The user record",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "AdminUser")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "AdminUser"))
      })
  @APIResponse(responseCode = ZenStatus.NOT_FOUND, description = "No user with that id (ZenError)")
  @Transactional
  public Response get(@PathParam("id") String id) {
    User user = findUser(id);
    if (user == null) {
      return notFound(id);
    }
    return Response.ok(toProto(user)).build();
  }

  @PUT
  @Path("/{id}")
  @Consumes({MediaType.APPLICATION_JSON, PROTOBUF})
  @Produces({MediaType.APPLICATION_JSON, PROTOBUF})
  @Operation(summary = "Update a user's editable fields")
  @RequestBody(content = @Content(schema = @Schema(ref = "AdminUser")))
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "The updated user record",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "AdminUser")),
        @Content(mediaType = PROTOBUF, schema = @Schema(ref = "AdminUser"))
      })
  @APIResponse(responseCode = ZenStatus.NOT_FOUND, description = "No user with that id (ZenError)")
  @Transactional
  public Response update(@PathParam("id") String id, AdminUser incoming) {
    User user = findUser(id);
    if (user == null) {
      return notFound(id);
    }
    // Only the admin-editable subset is applied; id, email, and timestamps are read-only here.
    if (!incoming.getRole().isEmpty()) {
      user.role = UserRole.fromValue(incoming.getRole());
    }
    user.displayName = emptyToNull(incoming.getDisplayName());
    user.nickname = emptyToNull(incoming.getNickname());
    user.language = emptyToNull(incoming.getLanguage());
    user.isPremium = incoming.getIsPremium();
    user.isPrivate = incoming.getIsPrivate();
    user.persist();
    return Response.ok(toProto(user)).build();
  }

  // --- helpers -------------------------------------------------------------------------------

  private static User findUser(String id) {
    UUID uuid;
    try {
      uuid = UUID.fromString(id);
    } catch (IllegalArgumentException e) {
      return null;
    }
    return User.findById(uuid);
  }

  private static Response notFound(String id) {
    ZenError error =
        ZenError.newBuilder().setCode(ERROR_NOT_FOUND).setMessage("No user with id " + id).build();
    return Response.status(Response.Status.NOT_FOUND).entity(error).build();
  }

  /** Parses the ra-data-simple-rest {@code range=[start,end]} (inclusive), defaulting to page 0. */
  private static int[] parseRange(String range) throws Exception {
    if (range == null || range.isBlank()) {
      return new int[] {0, DEFAULT_PAGE_SIZE - 1};
    }
    int[] parsed = JSON.readValue(range, int[].class);
    int start = Math.max(0, parsed.length > 0 ? parsed[0] : 0);
    int end = parsed.length > 1 ? parsed[1] : start + DEFAULT_PAGE_SIZE - 1;
    if (end < start) {
      end = start;
    }
    return new int[] {start, end};
  }

  /** Parses {@code sort=[field,order]} into a Panache {@link Sort} over a whitelisted column. */
  private static Sort buildSort(String sort) throws Exception {
    String field = DEFAULT_SORT_PROPERTY;
    boolean ascending = false;
    if (sort != null && !sort.isBlank()) {
      String[] parsed = JSON.readValue(sort, String[].class);
      if (parsed.length > 0 && SORTABLE.containsKey(parsed[0])) {
        field = SORTABLE.get(parsed[0]);
        ascending = parsed.length < 2 || !ORDER_DESCENDING.equalsIgnoreCase(parsed[1]);
      }
    }
    return Sort.by(field, ascending ? Sort.Direction.Ascending : Sort.Direction.Descending);
  }

  /** Builds the HQL where clause from the ra filter; empty string means "all rows". */
  private static String buildFilter(String filter) throws Exception {
    JsonNode node = filterNode(filter);
    StringBuilder where = new StringBuilder();
    if (node.hasNonNull(FILTER_ROLE)) {
      where.append(FILTER_ROLE).append(" = :").append(FILTER_ROLE);
    }
    if (node.hasNonNull(FILTER_QUERY)) {
      if (where.length() > 0) {
        where.append(" and ");
      }
      where.append("lower(email) like :").append(FILTER_QUERY);
    }
    return where.toString();
  }

  private static Map<String, Object> filterParams(String filter) throws Exception {
    JsonNode node = filterNode(filter);
    Map<String, Object> params = new HashMap<>();
    if (node.hasNonNull(FILTER_ROLE)) {
      params.put(FILTER_ROLE, UserRole.fromValue(node.get(FILTER_ROLE).asText()));
    }
    if (node.hasNonNull(FILTER_QUERY)) {
      params.put(FILTER_QUERY, "%" + node.get(FILTER_QUERY).asText().toLowerCase() + "%");
    }
    return params;
  }

  private static JsonNode filterNode(String filter) throws Exception {
    if (filter == null || filter.isBlank()) {
      return JSON.createObjectNode();
    }
    return JSON.readTree(filter);
  }

  private static String emptyToNull(String value) {
    return value == null || value.isEmpty() ? null : value;
  }

  /** Projects a {@code users} row into the {@link AdminUser} proto (the DemoResource.toProfile pattern). */
  private static AdminUser toProto(User user) {
    AdminUser.Builder builder =
        AdminUser.newBuilder()
            .setId(user.id.toString())
            .setEmail(nullToEmpty(user.email))
            .setDisplayName(nullToEmpty(user.displayName))
            .setNickname(nullToEmpty(user.nickname))
            .setRole(user.role == null ? "" : user.role.toString())
            .setLanguage(nullToEmpty(user.language))
            .setIsPremium(user.isPremium)
            .setIsPrivate(user.isPrivate)
            .setEmailVerified(user.emailVerified)
            .setCreatedAtMs(toEpochMs(user.createdAt));
    if (user.lastLoginAt != null) {
      builder.setLastLoginAtMs(toEpochMs(user.lastLoginAt));
    }
    return builder.build();
  }

  private static long toEpochMs(OffsetDateTime time) {
    return time == null ? 0L : time.toInstant().toEpochMilli();
  }

  private static String nullToEmpty(String value) {
    return value == null ? "" : value;
  }
}
