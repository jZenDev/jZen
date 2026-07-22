package zen.identity.user;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * The {@code users} table (active-record Panache entity). Ported from
 * ../BugEater/bugeater-quarkus/src/main/java/jlogicsoftware/user/User.java.
 *
 * <p>The primary key {@code id} is the Supabase {@code auth.users.id} (the JWT {@code sub});
 * it is assigned from the token, never generated here. This table carries no learning-domain
 * columns; the columns it does carry are identity plus two first-class product concerns of
 * the scaffold:
 *
 * <ul>
 *   <li><strong>Payment:</strong> {@code is_premium}.
 *   <li><strong>GDPR / data retention:</strong> {@code analytics_consent},
 *       {@code deletion_warning_sent_at}, {@code final_warning_sent_at}.
 * </ul>
 *
 * The deletion-warning timestamps are written by {@link UserRetentionService} (ROADMAP step 6);
 * {@code is_premium} both exempts an account from that cycle and awaits payments in step 7.
 * {@code language} feeds i18n and is the sole locale source for email, which has no request to
 * read {@code Accept-Language} from.
 */
@Entity
@Table(name = "users")
public class User extends PanacheEntityBase {

  @Id public UUID id;

  @Column(name = "nickname")
  public String nickname;

  @Column(name = "display_name")
  public String displayName;

  @Column(nullable = false)
  public String email;

  @Column(name = "email_verified", nullable = false)
  public boolean emailVerified;

  @Column(name = "avatar_url")
  public String avatarUrl;

  @Column(name = "language")
  public String language;

  @Column(name = "theme")
  public String theme;

  @Column(name = "is_private", nullable = false)
  public boolean isPrivate;

  @Column(nullable = false)
  public UserRole role;

  @Column(name = "created_at", nullable = false)
  public OffsetDateTime createdAt;

  @Column(name = "last_login_at")
  public OffsetDateTime lastLoginAt;

  @Column(name = "accepted_terms", nullable = false)
  public boolean acceptedTerms;

  // GDPR / data-retention.
  @Column(name = "analytics_consent")
  public String analyticsConsent;

  // Payment.
  @Column(name = "is_premium", nullable = false)
  public boolean isPremium;

  // GDPR / data-retention.
  @Column(name = "deletion_warning_sent_at")
  public OffsetDateTime deletionWarningSentAt;

  @Column(name = "final_warning_sent_at")
  public OffsetDateTime finalWarningSentAt;
}
