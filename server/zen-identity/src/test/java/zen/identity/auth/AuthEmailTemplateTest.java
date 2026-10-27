package zen.identity.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

/** The shipped GoTrue templates must name the application in both the link and its visible text. */
class AuthEmailTemplateTest {

  private static final String SITE = "https://app.example.test";
  private static final String REDIRECT = "https://app.example.test/auth/callback";
  private static final Pattern HREF = Pattern.compile("href=\"([^\"]+)\"");

  @Test
  void signupAndRecoveryLinksUseTheApplicationOrigin() throws IOException {
    for (String[] fixture : new String[][] {{"confirmation.html", "signup"}, {"recovery.html", "recovery"}}) {
      String template = fixture[0];
      String type = fixture[1];
      String rendered = render(template);
      Matcher href = HREF.matcher(rendered);
      assertTrue(href.find(), template + " must contain a link");

      URI link = URI.create(href.group(1).replace("&amp;", "&"));
      assertEquals(SITE, link.getScheme() + "://" + link.getAuthority());
      assertTrue(link.getPath().endsWith("/auth/confirm"));
      assertTrue(link.getRawQuery().contains("token_hash=example-hash"));
      assertTrue(link.getRawQuery().contains("type=" + type));
      assertTrue(link.getRawQuery().contains("next=" + URLEncoder.encode(REDIRECT, StandardCharsets.UTF_8)));
      assertFalse(rendered.contains("supabase.co"), template + " must not expose the provider host");

      String visibleText = rendered.replaceAll("<[^>]*>", " ").replace("&amp;", "&");
      assertTrue(visibleText.contains(SITE + "/auth/confirm"), template + " must show the app origin");
    }
  }

  private static String render(String name) throws IOException {
    try (var stream = AuthEmailTemplateTest.class.getResourceAsStream("/email-templates/" + name)) {
      if (stream == null) {
        throw new IOException("Missing reference email template: " + name);
      }
      String template = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
      return template
          .replace("{{ .SiteURL }}", SITE)
          .replace("{{ .TokenHash }}", "example-hash")
          .replace("{{ .RedirectTo | urlquery }}", URLEncoder.encode(REDIRECT, StandardCharsets.UTF_8));
    }
  }
}
