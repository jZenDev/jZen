/**
 * Compile-time admin config (Vite env only; runtime client config is forbidden - STANDARDS.md
 * "Client config is compile-time"). The REST prefix lives in exactly one place here; the framework
 * scaffold (@jzen/admin-core) takes the resolved bases as parameters and hardcodes nothing.
 */

/** Same-origin default; the Vite dev server proxies it to the backend. Override with VITE_API_URL. */
const DEFAULT_API_BASE = "/api/v1";

const apiBase = import.meta.env.VITE_API_URL ?? DEFAULT_API_BASE;

/** Base for the framework admin resources (users, ...). */
export const adminApiBase = `${apiBase}/admin`;

/** Base for the framework auth surface (login, logout, identity). */
export const authApiBase = `${apiBase}/auth`;
