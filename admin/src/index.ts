/**
 * @jzen/admin-core - the framework's reusable react-admin scaffolding.
 *
 * A type-generic toolkit an app's admin assembles: a credentialed data provider wired to jZen's
 * Content-Range pagination, an auth provider backed by the framework's Supabase session, and a
 * login page. Domain resources and their generated types live in each app's admin, not here.
 */
export { createDataProvider } from "./dataProvider";
export { createAuthProvider } from "./authProvider";
export { LoginPage } from "./LoginPage";
export {
  CSRF_COOKIE,
  HttpHeader,
  HttpMethod,
  HttpStatus,
  MediaType,
  Role,
  Transport,
} from "./http";
