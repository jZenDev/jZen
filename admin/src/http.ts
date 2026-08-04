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

/**
 * The JS-readable CSRF cookie the backend issues, beside the httpOnly session cookie.
 *
 * It is readable on purpose: the backend enforces a double-submit check, so the panel has to echo
 * this value in {@link HttpHeader.Csrf} on every mutating call. A page on another origin can make
 * the browser send the cookie but cannot read it, which is what the check turns into a refusal.
 */
export const CSRF_COOKIE = "XSRF-TOKEN";

/**
 * Reads a cookie value by name; returns undefined off-DOM or when absent.
 *
 * Absent is an ordinary answer, not an error: the token expires with the access token it was
 * issued alongside, and the backend only enforces the echo while that access cookie is present.
 */
export function readCookie(name: string): string | undefined {
  if (typeof document === "undefined") {
    return undefined;
  }
  const match = document.cookie
    .split("; ")
    .find((row) => row.startsWith(`${name}=`));
  return match ? decodeURIComponent(match.slice(name.length + 1)) : undefined;
}

/** Authority roles; mirrors zen.identity.user.UserRole.Names. */
export enum Role {
  Admin = "admin",
}
