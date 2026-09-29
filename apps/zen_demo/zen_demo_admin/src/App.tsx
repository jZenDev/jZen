import {
  createAuthProvider,
  createDataProvider,
  darkTheme,
  Layout,
  lightTheme,
  LoginPage,
} from "@jzen/admin-core";
import {
  Admin,
  type AuthProvider,
  type DataProvider,
  Resource,
} from "react-admin";
import { adminApiBase, authApiBase } from "./config";
import { UserEdit, UserList, UserShow } from "./resources/User";

const apiDataProvider = createDataProvider(adminApiBase);
const apiAuthProvider = createAuthProvider(authApiBase);

/**
 * The zen_demo reference app's admin panel (ROADMAP step 5). It assembles the framework scaffold
 * (@jzen/admin-core) and registers this app's domain resources, typed off the generated OpenAPI
 * schema. The API bases come from ./config (the single place the REST prefix lives); the Vite dev
 * proxy keeps them same-origin so the session cookie flows.
 *
 * The providers default to that live API; a test passes in-memory ones to render the real panel.
 */
export function App({
  dataProvider = apiDataProvider,
  authProvider = apiAuthProvider,
}: {
  dataProvider?: DataProvider;
  authProvider?: AuthProvider;
}) {
  return (
    <Admin
      dataProvider={dataProvider}
      authProvider={authProvider}
      loginPage={LoginPage}
      layout={Layout}
      lightTheme={lightTheme}
      darkTheme={darkTheme}
    >
      <Resource name="users" list={UserList} show={UserShow} edit={UserEdit} />
    </Admin>
  );
}
