package dev.zen.app.demo;

import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Minimal server-side localization for the demo endpoints, mirroring how DartZen's ZenDemo
 * server localized its {@code /ping} message
 * (../DartZen/apps/ZenDemo/dartzen_demo_server/lib/src/l10n). Messages are data, not code:
 * they live in {@code src/main/resources/demo-l10n/messages_<lang>.properties} and are loaded
 * once at startup. Supported locales are {@code {en, uk}} (the jZen baseline, replacing the
 * donor's {@code {en, pl}}); {@code en} is the fallback.
 *
 * <p>This is the demo's own small mechanism, deliberately independent of the localized email
 * templates coming in ROADMAP step 6 (a Qute {@code @MessageBundle} keyed off
 * {@code users.language}). Both read locale the same way the rest of the stack does - from the
 * request - and both start at {@code {en, uk}}.
 */
@ApplicationScoped
public class DemoMessages {

  /** Supported locales, in preference order; the first is the fallback. */
  public static final List<String> SUPPORTED = List.of("en", "uk");

  private final Map<String, Properties> byLocale = new ConcurrentHashMap<>();

  @PostConstruct
  void load() {
    for (String locale : SUPPORTED) {
      byLocale.put(locale, read("demo-l10n/messages_" + locale + ".properties"));
    }
  }

  private Properties read(String resource) {
    Properties props = new Properties();
    try (InputStream in = Thread.currentThread().getContextClassLoader().getResourceAsStream(resource)) {
      if (in == null) {
        throw new IllegalStateException("Missing demo localization resource: " + resource);
      }
      /* UTF-8 so Cyrillic (uk) survives; Properties.load(InputStream) would assume ISO-8859-1. */
      try (Reader reader = new InputStreamReader(in, StandardCharsets.UTF_8)) {
        props.load(reader);
      }
    } catch (IOException e) {
      throw new UncheckedIOException("Failed to load " + resource, e);
    }
    return props;
  }

  /**
   * Resolves an {@code Accept-Language} header to a supported locale, falling back to the first
   * {@link #SUPPORTED} entry ({@code en}). Only the primary language subtag of the first tag is
   * considered (e.g. {@code "uk-UA,uk;q=0.9,en;q=0.8"} resolves to {@code uk}).
   */
  public String resolveLocale(String acceptLanguage) {
    if (acceptLanguage == null || acceptLanguage.isBlank()) {
      return SUPPORTED.get(0);
    }
    String primary =
        acceptLanguage.split(",")[0].split(";")[0].trim().split("-")[0].toLowerCase();
    return SUPPORTED.contains(primary) ? primary : SUPPORTED.get(0);
  }

  /** Returns the message for {@code key} in the given {@code locale}, falling back to English. */
  public String get(String key, String locale) {
    Properties props = byLocale.getOrDefault(locale, byLocale.get(SUPPORTED.get(0)));
    String value = props.getProperty(key);
    if (value == null) {
      value = byLocale.get(SUPPORTED.get(0)).getProperty(key);
    }
    return value != null ? value : key;
  }
}
