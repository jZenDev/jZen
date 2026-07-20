/**
 * Shared HTTP + transport constants for the jZen admin scaffold.
 *
 * Centralized so no status number, method, or header name is a magic literal in the providers -
 * the TypeScript mirror of the server's `ZenStatus` (zen.core.http) and `ZenTransportFormat`
 * (zen.transport).
 */

/** HTTP status codes the providers branch on. */
export enum HttpStatus {
  Ok = 200,
  NoContent = 204,
  Unauthorized = 401,
  Forbidden = 403,
}

/** HTTP methods, as `fetch`'s `method` values. */
export enum HttpMethod {
  Get = "GET",
  Head = "HEAD",
  Post = "POST",
  Put = "PUT",
}

/** HTTP header names. */
export enum HttpHeader {
  Accept = "Accept",
  ContentType = "Content-Type",
  Csrf = "X-CSRF-Token",
}

/** Media types. */
export enum MediaType {
  Json = "application/json",
}

/** The dual-mode transport seam: the header, and the JSON value the admin always sends. */
export const Transport = {
  header: "X-Zen-Transport",
  json: "json",
} as const;

/** The JS-readable CSRF cookie the backend issues (TA-4). */
export const CSRF_COOKIE = "XSRF-TOKEN";

/** Authority roles; mirrors zen.identity.user.UserRole.Names. */
export enum Role {
  Admin = "admin",
}
