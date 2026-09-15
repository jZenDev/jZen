package zen.identity;

import zen.identity.user.User;
import zen.identity.user.UserRetentionService;
import zen.identity.user.UserRole;
import zen.proto.v1.Identity;
import java.time.OffsetDateTime;
import java.util.UUID;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.Named;

/**
 * Maps the {@code User} entity to its wire {@link Identity} proto (the projection every auth
 * endpoint returns). A MapStruct mapper so it is a CDI-managed, generated bean the resources
 * inject by type, keeping the transport concern out of the entity.
 *
 * <p>MapStruct implements the abstract {@link #toView} (the field-by-field entity mapping,
 * with the named converters below: UUID to String, {@code UserRole} to String,
 * {@code OffsetDateTime} to epoch-millis). The {@code Identity} proto is assembled from that
 * view in the concrete {@link #toProto}: protobuf-generated messages are immutable builder
 * types whose repeated fields use {@code addAllRoles(...)} rather than a JavaBeans setter, so
 * they are not a MapStruct target; this is written as an abstract-class mapper precisely so
 * the proto assembly is a concrete helper MapStruct leaves alone.
 *
 * <p>Only {@code User -> Identity} is defined: the {@code User} is authoritative and always
 * sourced from Supabase, never reconstructed from the wire, so a reverse mapping has no use.
 */
@Mapper(componentModel = "cdi")
public abstract class IdentityMapper {

  /** Flat view of the wire-relevant {@code User} fields; MapStruct fills it in. */
  public record IdentityView(String id, String role, long createdAtMs, boolean emailVerified) {}

  @Mapping(target = "id", source = "id", qualifiedByName = "uuidToString")
  @Mapping(target = "role", source = "role", qualifiedByName = "roleToString")
  @Mapping(target = "createdAtMs", source = "createdAt", qualifiedByName = "toEpochMillis")
  @Mapping(target = "emailVerified", source = "emailVerified")
  abstract IdentityView toView(User user);

  /** Assembles the immutable {@link Identity} proto from the mapped view. */
  public Identity toProto(User user) {
    if (user == null) {
      return Identity.getDefaultInstance();
    }
    IdentityView view = toView(user);
    Identity.Builder builder =
        Identity.newBuilder()
            .setId(view.id() != null ? view.id() : "")
            .setLifecycleState(lifecycleState(user))
            .setCreatedAtMs(view.createdAtMs())
            .setEmailVerified(view.emailVerified());
    if (view.role() != null) {
      builder.addRoles(view.role());
    }
    return builder.build();
  }

  /**
   * Derives the wire {@code lifecycle_state} from the two retention timestamps and the
   * anonymisation predicate {@link UserRetentionService} already owns, rather than the hard-coded
   * {@code "active"} this used to return regardless of an account's actual state. Free: both facts
   * are already columns on the row in hand, so no query, no proto change, no new consumer contract.
   */
  private static String lifecycleState(User user) {
    if (UserRetentionService.isAnonymised(user)) {
      return "anonymised";
    }
    if (user.deletionWarningSentAt != null) {
      return "warned";
    }
    return "active";
  }

  @Named("uuidToString")
  static String uuidToString(UUID id) {
    return id == null ? null : id.toString();
  }

  @Named("roleToString")
  static String roleToString(UserRole role) {
    return role == null ? null : role.toString();
  }

  @Named("toEpochMillis")
  static long toEpochMillis(OffsetDateTime time) {
    return time == null ? 0L : time.toInstant().toEpochMilli();
  }
}
