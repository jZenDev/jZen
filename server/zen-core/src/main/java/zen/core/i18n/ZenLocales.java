package zen.core.i18n;

import java.util.List;

/**
 * The locales jZen ships, in one place. {@link #SUPPORTED} is the single declaration of the
 * supported set and {@link #FALLBACK} of the language used when nothing matches; every localized
 * surface resolves through here rather than repeating the list.
 *
 * <p>Two sources feed it, and they differ only in how the raw tag arrives:
 *
 * <ul>
 *   <li>a request header - {@link #fromAcceptLanguage(String)}, delegating to the pure
 *       {@link AcceptLanguage} parser (the demo REST surface);
 *   <li>stored user preference - {@link #resolve(String)} over the {@code users.language} column
 *       (localized email, which has no request to read a header from).
 * </ul>
 *
 * <p>The set grows with the message bundles and templates that back it: adding a locale means
 * adding a {@code @Localized} bundle variant and the per-locale templates, then listing it here.
 */
public final class ZenLocales {

  /** English - the fallback locale. */
  public static final String EN = "en";

  /** Ukrainian. */
  public static final String UK = "uk";

  /** Every locale tag jZen ships a message bundle and template set for. */
  public static final List<String> SUPPORTED = List.of(EN, UK);

  /** The locale used when a requested tag is absent, blank, or unsupported. */
  public static final String FALLBACK = EN;

  private ZenLocales() {}

  /**
   * Resolves a stored or explicitly chosen language tag (e.g. the {@code users.language} column)
   * to a supported locale, comparing only the primary subtag so {@code "uk-UA"} matches
   * {@code "uk"}. Returns {@link #FALLBACK} for null, blank, or unsupported input.
   */
  public static String resolve(String tag) {
    if (tag == null || tag.isBlank()) {
      return FALLBACK;
    }
    String primary = tag.trim().split("-")[0].toLowerCase();
    return SUPPORTED.contains(primary) ? primary : FALLBACK;
  }

  /**
   * Resolves an HTTP {@code Accept-Language} header against {@link #SUPPORTED}, falling back to
   * {@link #FALLBACK}. The parsing itself stays in {@link AcceptLanguage}, which knows nothing
   * about which locales jZen supports.
   */
  public static String fromAcceptLanguage(String header) {
    return AcceptLanguage.resolve(header, SUPPORTED, FALLBACK);
  }
}
