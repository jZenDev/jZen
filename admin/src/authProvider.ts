import type { AuthProvider } from "react-admin";
import { HttpHeader, HttpMethod, HttpStatus, MediaType, Role, Transport } from "./http";

/**
 * react-admin auth provider factory backed by the jZen framework auth surface (Supabase session).
 *
 * There is no parallel auth: it drives the same endpoints the Flutter clients use -
 * `POST {authBase}/login`, `POST {authBase}/logout`, and the `GET {authBase}/identity` probe
 * (200 = a session, 204 = anonymous). The session lives in the httpOnly `zen_access_token`
 * cookie, so auth state is never read from JS - it is decided by the identity probe, and every
 * request is credentialed.
 *
 * The panel is admin-only: login and checkAuth require the `admin` role (loaded server-side by
 * RoleAugmentor from the users table, never the JWT). A non-admin session is refused and cleared.
 */
export function createAuthProvider(authBase: string): AuthProvider {
  const jsonHeaders: HeadersInit = {
    [HttpHeader.ContentType]: MediaType.Json,
    [HttpHeader.Accept]: MediaType.Json,
    [Transport.header]: Transport.json,
  };

  async function fetchIdentity(): Promise<ZenIdentity | null> {
    const res = await fetch(`${authBase}/identity`, {
      headers: { [HttpHeader.Accept]: MediaType.Json, [Transport.header]: Transport.json },
      credentials: "include",
    });
    return res.status === HttpStatus.Ok ? ((await res.json()) as ZenIdentity) : null;
  }

  async function clearSession(): Promise<void> {
    await fetch(`${authBase}/logout`, { method: HttpMethod.Post, credentials: "include" });
  }

  return {
    async login({ username, password }) {
      const res = await fetch(`${authBase}/login`, {
        method: HttpMethod.Post,
        headers: jsonHeaders,
        credentials: "include",
        body: JSON.stringify({ email: username, password }),
      });
      if (!res.ok) {
        throw new Error("Invalid email or password");
      }
      const identity = (await res.json()) as ZenIdentity;
      if (!hasAdminRole(identity)) {
        await clearSession();
        throw new Error("This account is not authorized for the admin panel");
      }
    },

    async logout() {
      await clearSession();
    },

    async checkAuth() {
      const identity = await fetchIdentity();
      if (!identity || !hasAdminRole(identity)) {
        throw new Error("Not authenticated");
      }
    },

    async checkError(error) {
      const status = (error as { status?: number })?.status;
      if (status === HttpStatus.Unauthorized || status === HttpStatus.Forbidden) {
        throw new Error("Session expired");
      }
    },

    async getIdentity() {
      const identity = await fetchIdentity();
      if (!identity) {
        throw new Error("No active session");
      }
      return { id: identity.id, fullName: identity.id };
    },

    async getPermissions() {
      const identity = await fetchIdentity();
      return identity?.roles ?? [];
    },
  };
}

/** The subset of the Identity proto (proto3-JSON) the auth provider reads. */
interface ZenIdentity {
  id: string;
  roles?: string[];
}

function hasAdminRole(identity: ZenIdentity): boolean {
  return (identity.roles ?? []).includes(Role.Admin);
}
