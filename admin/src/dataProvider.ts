import simpleRestProvider from "ra-data-simple-rest";
import type { DataProvider } from "react-admin";
import { CSRF_COOKIE, HttpHeader, HttpMethod, MediaType, Transport } from "./http";

/**
 * react-admin data provider factory for the jZen REST API.
 *
 * The admin panel is the JSON half of the dual-mode transport: it always speaks
 * `X-Zen-Transport: json`. Protobuf binary is for native Flutter clients only, and `fetch` in a
 * browser gains nothing from it.
 *
 * Backend list endpoints follow the ra-data-simple-rest convention: a bare JSON array body plus a
 * `Content-Range: <unit> start-end/total` header (jZen's `AdminUserResource`), so the stock
 * provider's pagination works unchanged. The session lives in the httpOnly `zen_access_token`
 * cookie, so every request is credentialed and no token is read in JS.
 *
 * This is framework scaffolding: it binds to no app's schema. Each app's admin passes its own API
 * base and registers its own generated-typed resources.
 */
export function createDataProvider(apiBase: string): DataProvider {
  return simpleRestProvider(apiBase, async (url, options = {}) => {
    const headers = new Headers(options.headers ?? {});
    headers.set(Transport.header, Transport.json);
    headers.set(HttpHeader.Accept, MediaType.Json);

    // Echo the JS-readable XSRF-TOKEN on mutating requests. The backend issues it (TA-4) and does
    // not yet enforce it; sending it now is forward-looking hygiene. GET/HEAD carry no CSRF risk.
    const method = (options.method ?? HttpMethod.Get).toUpperCase();
    if (method !== HttpMethod.Get && method !== HttpMethod.Head) {
      const csrf = readCookie(CSRF_COOKIE);
      if (csrf) {
        headers.set(HttpHeader.Csrf, csrf);
      }
    }

    const response = await fetch(url, {
      ...options,
      headers,
      credentials: "include",
    });

    const text = await response.text();
    return {
      status: response.status,
      headers: response.headers,
      body: text,
      json: text ? JSON.parse(text) : undefined,
    };
  });
}

/** Reads a cookie value by name; returns undefined off-DOM or when absent. */
function readCookie(name: string): string | undefined {
  if (typeof document === "undefined") {
    return undefined;
  }
  const match = document.cookie
    .split("; ")
    .find((row) => row.startsWith(`${name}=`));
  return match ? decodeURIComponent(match.slice(name.length + 1)) : undefined;
}
