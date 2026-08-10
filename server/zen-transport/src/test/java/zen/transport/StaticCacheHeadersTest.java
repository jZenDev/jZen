package zen.transport;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

/**
 * Unit tests for {@link StaticCacheHeaders}' decisions.
 *
 * <p>A plain JUnit test, not a {@code @QuarkusTest}: what is asserted here is that the validator is
 * a function of the build stamp <em>and of nothing else</em>. That is precisely the property whose
 * absence caused F2 — the old validator was a function of when the process started — and it is a
 * property about the derivation, not about a running server. The served behaviour (the {@code ETag}
 * on a real response, the 304, and the 304 with a stale {@code If-Modified-Since} alongside) is
 * asserted against an assembled application in {@code StaticCacheHeadersWiringTest}, and across a
 * genuine container replacement by {@code task test:native}.
 */
class StaticCacheHeadersTest {

  // --- the validator is derived from the build, not from the process ------------------------

  @Test
  void etag_isAFunctionOfTheBuildStampAlone() {
    assertEquals(
        StaticCacheHeaders.etagOf("a1b2c3d"),
        StaticCacheHeaders.etagOf("a1b2c3d"),
        "the same build must produce the same validator, however many processes serve it — a"
            + " validator that varies per process is exactly the defect this replaced");
  }

  @Test
  void etag_changesWithTheBuildStamp() {
    assertNotEquals(
        StaticCacheHeaders.etagOf("20260808120000"),
        StaticCacheHeaders.etagOf("20260808120001"),
        "a rebuild must bust the cache, or a deploy is invisible to a returning browser");
  }

  @Test
  void etag_isStrongAndQuoted() {
    assertEquals("\"a1b2c3d\"", StaticCacheHeaders.etagOf("a1b2c3d"));
  }

  @Test
  void etag_scrubsCharactersThatWouldBreakTheHeader() {
    // An operator can set ZEN_BUILD_ID to anything; a quote in the value must not be able to close
    // the quoted string, and a newline must not be able to start a header.
    assertEquals("\"1.0-dirty\"", StaticCacheHeaders.etagOf("1.0-dirty"));
    assertEquals("\"-evil-\"", StaticCacheHeaders.etagOf("\"evil\""));
    assertEquals("\"a--b\"", StaticCacheHeaders.etagOf("a\r\nb"));
  }

  // --- If-None-Match matching ----------------------------------------------------------------

  @Test
  void ifNoneMatch_matchesTheCurrentValidator() {
    assertTrue(StaticCacheHeaders.matchesEtag("\"build-1\"", "\"build-1\""));
  }

  @Test
  void ifNoneMatch_fromAnEarlierBuildDoesNotMatch() {
    assertFalse(
        StaticCacheHeaders.matchesEtag("\"build-1\"", "\"build-2\""),
        "a validator from a previous build must miss, so the new bytes are actually sent");
  }

  @Test
  void ifNoneMatch_handlesListsWeakTagsAndWildcard() {
    assertTrue(StaticCacheHeaders.matchesEtag("\"other\", \"build-1\"", "\"build-1\""));
    assertTrue(StaticCacheHeaders.matchesEtag("W/\"build-1\"", "\"build-1\""));
    assertTrue(StaticCacheHeaders.matchesEtag("*", "\"build-1\""));
  }

  @Test
  void ifNoneMatch_absentOrBlankDoesNotMatch() {
    assertFalse(StaticCacheHeaders.matchesEtag(null, "\"build-1\""));
    assertFalse(StaticCacheHeaders.matchesEtag("  ", "\"build-1\""));
  }

  // --- which paths get a validator at all ----------------------------------------------------

  @Test
  void dynamicRoots_getNoValidator() {
    // A build-stable validator on a changing response would serve stale data, which is worse than
    // the bytes it would save.
    assertFalse(StaticCacheHeaders.isStaticResourcePath("/api/v1/health"));
    assertFalse(StaticCacheHeaders.isStaticResourcePath("/api/v1/demo/ws"));
    assertFalse(StaticCacheHeaders.isStaticResourcePath("/auth/callback"));
    assertFalse(StaticCacheHeaders.isStaticResourcePath("/.well-known/assetlinks.json"));
    assertFalse(StaticCacheHeaders.isStaticResourcePath("/q/health"));
  }

  @Test
  void staticResources_getAValidator() {
    assertTrue(StaticCacheHeaders.isStaticResourcePath("/"));
    assertTrue(StaticCacheHeaders.isStaticResourcePath("/main.dart.wasm"));
    assertTrue(StaticCacheHeaders.isStaticResourcePath("/canvaskit/skwasm.wasm"));
    assertTrue(StaticCacheHeaders.isStaticResourcePath("/assets/fonts/MaterialIcons-Regular.otf"));
    assertTrue(StaticCacheHeaders.isStaticResourcePath("/admin/assets/index-abc123.js"));
  }

  @Test
  void nonPaths_getNoValidator() {
    assertFalse(StaticCacheHeaders.isStaticResourcePath(null));
    assertFalse(StaticCacheHeaders.isStaticResourcePath(""));
    assertFalse(StaticCacheHeaders.isStaticResourcePath("main.dart.wasm"));
  }

  // --- mustRevalidate, unchanged by this wave -------------------------------------------------

  @Test
  void fixedNameEntryFiles_mustRevalidate() {
    assertTrue(StaticCacheHeaders.mustRevalidate("/"));
    assertTrue(StaticCacheHeaders.mustRevalidate("/admin/"));
    assertTrue(StaticCacheHeaders.mustRevalidate("/index.html"));
    assertTrue(StaticCacheHeaders.mustRevalidate("/admin/index.html"));
    assertTrue(StaticCacheHeaders.mustRevalidate("/flutter_bootstrap.js"));
    assertTrue(StaticCacheHeaders.mustRevalidate("/main.dart.wasm"));
    assertTrue(StaticCacheHeaders.mustRevalidate("/version.json"));
  }

  @Test
  void contentHashedAndSdkFiles_keepTheLongCache() {
    assertFalse(StaticCacheHeaders.mustRevalidate("/admin/assets/index-abc123.js"));
    assertFalse(StaticCacheHeaders.mustRevalidate("/canvaskit/skwasm.wasm"));
    assertFalse(StaticCacheHeaders.mustRevalidate("/assets/AssetManifest.bin"));
    assertFalse(StaticCacheHeaders.mustRevalidate(null));
  }
}
