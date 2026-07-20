package dev.zen.core.i18n;

import java.util.List;

/**
 * Resolves an HTTP {@code Accept-Language} header to a supported locale tag. A framework-free pure
 * function (no Quarkus, no JAX-RS), so any jZen module reuses it - the reference backend's demo
 * endpoints today, and any other request-localized surface tomorrow. Locale resolution for
 * non-request contexts (e.g. email keyed off {@code users.language}) does not use this; it resolves
 * the tag differently but feeds the same typed Qute {@code @MessageBundle} mechanism.
 */
public final class AcceptLanguage {

  private AcceptLanguage() {}

  /**
   * Returns the first {@code supported} tag whose primary language subtag matches an entry of the
   * {@code Accept-Language} header, in header order, or {@code fallback} when none match or the
   * header is blank. Only the primary subtag is compared (e.g. {@code "uk-UA"} matches {@code "uk"});
   * q-values are ignored beyond the order in which tags appear.
   *
   * @param header the raw {@code Accept-Language} header value (may be null)
   * @param supported the supported locale tags, e.g. {@code List.of("en", "uk")}
   * @param fallback the tag to return when nothing matches (typically the first supported)
   */
  public static String resolve(String header, List<String> supported, String fallback) {
    if (header != null && !header.isBlank()) {
      for (String entry : header.split(",")) {
        String primary = entry.split(";")[0].trim().split("-")[0].toLowerCase();
        if (!primary.isEmpty() && supported.contains(primary)) {
          return primary;
        }
      }
    }
    return fallback;
  }
}
