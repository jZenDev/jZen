package zen.core.i18n;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.List;
import java.util.Locale;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * F16: a locale-insensitive {@code toLowerCase()} used to feed this parser, and in the Turkish
 * locale {@code "I".toLowerCase()} is {@code "ı"} (dotless), not {@code "i"} - so a tag like
 * {@code "EN"} would fail to match {@code "en"} whenever the JVM's default locale happened to be
 * Turkish. Forcing that default here is the only way to prove the fix: every other locale agrees
 * with {@link Locale#ROOT} on ASCII case folding, so the bug is invisible under any locale but
 * this one.
 */
class ZenLocalesTest {

  private Locale originalDefault;

  @BeforeEach
  void forceTurkishDefault() {
    originalDefault = Locale.getDefault();
    Locale.setDefault(new Locale("tr"));
  }

  @AfterEach
  void restoreDefault() {
    Locale.setDefault(originalDefault);
  }

  @Test
  void resolveIsCaseInsensitiveEvenUnderTheTurkishLocale() {
    assertEquals("en", ZenLocales.resolve("EN", List.of("en", "uk")));
    assertEquals("uk", ZenLocales.resolve("UK-UA", List.of("en", "uk")));
  }

  @Test
  void fromAcceptLanguageIsCaseInsensitiveEvenUnderTheTurkishLocale() {
    assertEquals("en", ZenLocales.fromAcceptLanguage("EN-US,UK;q=0.5", List.of("en", "uk")));
  }
}
