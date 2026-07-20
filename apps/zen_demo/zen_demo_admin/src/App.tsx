import { createAuthProvider, createDataProvider, LoginPage } from "@jzen/admin-core";
import { Admin, Resource } from "react-admin";
import { adminApiBase, authApiBase } from "./config";
import { UserEdit, UserList, UserShow } from "./resources/User";

/**
 * The zen_demo reference app's admin panel (ROADMAP step 5). It assembles the framework scaffold
 * (@jzen/admin-core) and registers this app's domain resources, typed off the generated OpenAPI
 * schema. The API bases come from ./config (the single place the REST prefix lives); the Vite dev
 * proxy keeps them same-origin so the session cookie flows.
 */
const dataProvider = createDataProvider(adminApiBase);
const authProvider = createAuthProvider(authApiBase);

export function App() {
  return (
    <Admin dataProvider={dataProvider} authProvider={authProvider} loginPage={LoginPage}>
      <Resource name="users" list={UserList} show={UserShow} edit={UserEdit} />
    </Admin>
  );
}
