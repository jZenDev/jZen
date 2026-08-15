package zen.core.i18n;

import java.util.List;

/**
 * The locales jZen itself ships messages and templates for. {@link #SHIPPED} is the single
 * declaration of that inventory and {@link #FALLBACK} of the language used when nothing matches.
 *
 * <p><strong>{@code SHIPPED} is an inventory, not a policy</strong> (ADR-044). It says which
 * locales <em>jZen's own</em> bundles and templates cover. It is <em>not</em> the set of languages
 * an application supports: that is the application's decision, supplied at runtime as
 * {@code zen.i18n.supported} and passed to the two-argument {@link #resolve(String, List)} /
 * {@link #fromAcceptLanguage(String, List)}. An application may support a language jZen ships
 * nothing for; {@code users.language} then holds that tag, and it is the application's own
 * templates and bundles that render it.
 *
 * <p>Two sources feed resolution, and they differ only in how the raw tag arrives:
 *
 * <ul>
 *   <li>a request header - {@link #fromAcceptLanguage(String, List)}, delegating to the pure
 *       {@link AcceptLanguage} parser;
 *   <li>stored user preference - {@link #resolve(String, List)} over the {@code users.language}
 *       column (localized email, which has no request to read a header from).
 * </ul>
 *
 * <p>The single-argument forms resolve against {@link #SHIPPED} and mean exactly that: "narrow
 * this to something jZen has strings for". Reach for them only when the framework's own inventory
 * is genuinely the question.
 *
 * <p>{@link #SHIPPED} grows with the message bundles and templates that back it: adding a locale
 * <em>to jZen</em> means adding a {@code @Localized} bundle variant and the per-locale templates,
 * then listing it here. Adding one to an application touches neither.
 */
public final class ZenLocales {

  /** English - the fallback locale. */
  public static final String EN = "en";

  /** Ukrainian. */
  public static final String UK = "uk";

  /**
   * Every locale tag jZen itself ships a message bundle and template set for.
   *
   * <p>The default an application's {@code zen.i18n.supported} starts from, and a floor rather
   * than a ceiling on what that application may support.
   */
  public static final List<String> SHIPPED = List.of(EN, UK);

  /** The locale used when a requested tag is absent, blank, or unmatched. */
  public static final String FALLBACK = EN;

  private ZenLocales() {}

  /**
   * Resolves a stored or explicitly chosen language tag (e.g. the {@code users.language} column)
   * against {@code supported}, comparing only the primary subtag so {@code "uk-UA"} matches
   * {@code "uk"}. Returns {@link #FALLBACK} for null, blank, or unmatched input.
   *
   * <p>{@code supported} is the <em>application's</em> set. Pass it wherever the answer becomes a
   * user-visible language, so a tag jZen ships nothing for survives instead of being clamped.
   */
  public static String resolve(String tag, List<String> supported) {
    if (tag == null || tag.isBlank()) {
      return FALLBACK;
    }
    String primary = tag.trim().split("[-_]")[0].toLowerCase();
    return supported.contains(primary) ? primary : FALLBACK;
  }

  /** Resolves against {@link #SHIPPED} - the locales jZen itself has strings for. */
  public static String resolve(String tag) {
    return resolve(tag, SHIPPED);
  }

  /**
   * Resolves an HTTP {@code Accept-Language} header against {@code supported}, falling back to
   * {@link #FALLBACK}. The parsing itself stays in {@link AcceptLanguage}, which knows nothing
   * about which locales anyone supports.
   */
  public static String fromAcceptLanguage(String header, List<String> supported) {
    return AcceptLanguage.resolve(header, supported, FALLBACK);
  }

  /** Resolves against {@link #SHIPPED} - the locales jZen itself has strings for. */
  public static String fromAcceptLanguage(String header) {
    return fromAcceptLanguage(header, SHIPPED);
  }
}
