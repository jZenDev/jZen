package zen.identity.user;

import jakarta.persistence.AttributeConverter;

/**
 * Application-managed user role. Roles live in the {@code users} table, never in the JWT
 * (see {@code RoleAugmentor}). Ported from
 * ../BugEater/bugeater-quarkus/src/main/java/jlogicsoftware/application/UserRole.java (the
 * donor's Eclipse JDT {@code @Nullable} annotations are dropped; jZen does not depend on JDT).
 */
public enum UserRole {
  USER(Names.USER),
  ADMIN(Names.ADMIN),
  REVIEWER(Names.REVIEWER),
  B2B_ADMIN(Names.B2B_ADMIN);

  /**
   * The role names as compile-time {@code String} constants, and the single source of the wire
   * values the enum wraps. Annotations such as {@code @RolesAllowed} require a constant expression
   * (JLS 15.29), which an enum method call ({@code UserRole.ADMIN.toString()}) is not - reference
   * these there instead, e.g. {@code @RolesAllowed(UserRole.Names.ADMIN)}. The same ADR-003
   * reasoning behind {@code ZenStatus}.
   */
  public static final class Names {
    private Names() {}

    public static final String USER = "user";
    public static final String ADMIN = "admin";
    public static final String REVIEWER = "reviewer";
    public static final String B2B_ADMIN = "b2b_admin";
  }

  private final String value;

  UserRole(String value) {
    this.value = value;
  }

  @Override
  public String toString() {
    return value;
  }

  public static UserRole fromValue(String v) {
    if (v == null) {
      return null;
    }
    for (UserRole r : values()) {
      if (r.value.equalsIgnoreCase(v)) {
        return r;
      }
    }
    throw new IllegalArgumentException("Unknown UserRole: " + v);
  }

  /** Maps the enum to and from its {@code users.role} string column. */
  @jakarta.persistence.Converter(autoApply = true)
  public static class Converter implements AttributeConverter<UserRole, String> {
    @Override
    public String convertToDatabaseColumn(UserRole attr) {
      return attr == null ? null : attr.value;
    }

    @Override
    public UserRole convertToEntityAttribute(String dbData) {
      return dbData == null ? null : UserRole.fromValue(dbData);
    }
  }
}
