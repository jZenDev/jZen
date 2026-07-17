import { Admin, Resource } from "react-admin";

import { dataProvider } from "./api/dataProvider";

/**
 * jZen admin panel. Replaces DartZen's Flutter `dartzen_ui_admin`
 * (../DartZen/packages/dartzen_ui_admin), which is dropped along with its example app.
 *
 * Scaffolded clean rather than adopted: nothing in ../BugEater uses react-admin, none
 * of its three React apps has an admin or CRUD screen, and their conventions conflict
 * three ways (CSS Modules + Radix vs Bootstrap vs Tailwind v4 + shadcn) across React
 * 18.3.1 and 19.2.3. There was no house standard to inherit.
 *
 * Resources are registered here as `.proto` models land. Empty until ROADMAP step 5.
 */
export function App() {
  return (
    <Admin dataProvider={dataProvider}>
      {/* e.g. <Resource name="users" list={UserList} edit={UserEdit} /> */}
      <Resource name="_placeholder" />
    </Admin>
  );
}
