import simpleRestProvider from "ra-data-simple-rest";
import type { DataProvider } from "react-admin";

/**
 * react-admin data provider for the jZen REST API.
 *
 * The admin panel is the JSON half of the dual-mode transport: it always speaks
 * `X-Zen-Transport: json`. Protobuf binary is for native Flutter clients only, and
 * `fetch` in a browser gains nothing from it.
 *
 * Types for the resources this talks to are generated, never hand-written:
 *   task sync:contracts  ->  openapi.json  ->  src/api/schema.generated.ts
 *
 * ra-data-simple-rest expects list responses to carry a Content-Range header for
 * pagination. Wiring that to the backend's paging convention is ROADMAP step 5; until
 * a resource exists there is nothing to page.
 */
const baseUrl = import.meta.env.VITE_API_URL ?? "/api/v1";

export const dataProvider: DataProvider = simpleRestProvider(
  baseUrl,
  async (url, options = {}) => {
    const headers = new Headers(options.headers ?? {});
    headers.set("X-Zen-Transport", "json");
    headers.set("Accept", "application/json");

    const response = await fetch(url, {
      ...options,
      headers,
      // Session lives in the zen_access_token cookie. Unlike BugEater we can use a
      // normally-named cookie: there is no Firebase Hosting edge stripping everything
      // except __session (its ADR-034).
      credentials: "include",
    });

    const text = await response.text();
    return {
      status: response.status,
      headers: response.headers,
      body: text,
      json: text ? JSON.parse(text) : undefined,
    };
  },
);
