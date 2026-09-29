/**
 * @jzen/admin-core - the framework's reusable react-admin scaffolding.
 *
 * A type-generic toolkit an app's admin assembles: a credentialed data provider wired to jZen's
 * Content-Range pagination, an auth provider backed by the framework's Supabase session, a
 * login page, and the layout and themes that keep the panel keyboard- and screen-reader-usable
 * (STANDARDS "Accessibility"). Domain resources and their generated types live in each app's
 * admin, not here.
 */
export { createDataProvider } from "./dataProvider";
export { createAuthProvider } from "./authProvider";
export { LoginPage } from "./LoginPage";
export { Layout } from "./Layout";
export { darkTheme, lightTheme } from "./theme";
export {
  CSRF_COOKIE,
  HttpHeader,
  HttpMethod,
  HttpStatus,
  MediaType,
  readCookie,
  Role,
  Transport,
} from "./http";
