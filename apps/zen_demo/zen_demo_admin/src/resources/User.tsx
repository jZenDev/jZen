import {
  BooleanField,
  BooleanInput,
  Datagrid,
  DateField,
  Edit,
  EditButton,
  EmailField,
  List,
  SaveButton,
  SelectInput,
  Show,
  ShowButton,
  SimpleForm,
  SimpleShowLayout,
  TextField,
  TextInput,
  Toolbar,
} from "react-admin";
import type { components } from "../api/schema.generated";

/** The generated admin-user record shape; the resource fields below are typed against it. */
export type AdminUser = components["schemas"]["AdminUser"];

// Role choices derived from the generated field type, so the enum stays in lockstep with proto.
const roles: NonNullable<AdminUser["role"]>[] = [
  "user",
  "admin",
  "reviewer",
  "b2b_admin",
];
const roleChoices = roles.map((role) => ({ id: role, name: role }));

export function UserList() {
  return (
    <List sort={{ field: "createdAtMs", order: "DESC" }}>
      {/* No bulk actions: react-admin's only default one is delete, and the API has no DELETE
          for users. Its row checkboxes also fail WCAG 4.1.2 — the "Select this row" label lands
          on a role-less wrapper, leaving each <input type=checkbox> unnamed. */}
      <Datagrid rowClick="show" bulkActionButtons={false}>
        <EmailField source="email" />
        <TextField source="displayName" />
        <TextField source="role" />
        <BooleanField source="isPremium" />
        <DateField source="createdAtMs" label="Created" showTime />
        {/* rowClick is a mouse-only onClick on the <tr>: no tab stop, no key handler. These are
            the keyboard's way into a record (WCAG 2.1.1); without them the list is a dead end. */}
        <ShowButton />
        <EditButton />
      </Datagrid>
    </List>
  );
}

export function UserShow() {
  return (
    <Show>
      <SimpleShowLayout>
        <TextField source="id" />
        <EmailField source="email" />
        <TextField source="displayName" />
        <TextField source="nickname" />
        <TextField source="role" />
        <TextField source="language" />
        <BooleanField source="isPremium" />
        <BooleanField source="isPrivate" />
        <BooleanField source="emailVerified" />
        <DateField source="createdAtMs" label="Created" showTime />
        <DateField source="lastLoginAtMs" label="Last login" showTime />
      </SimpleShowLayout>
    </Show>
  );
}

export function UserEdit() {
  return (
    <Edit>
      {/* Save only: the default toolbar's Delete calls an endpoint the API does not have. */}
      <SimpleForm
        toolbar={
          <Toolbar>
            <SaveButton />
          </Toolbar>
        }
      >
        <TextField source="id" />
        <EmailField source="email" />
        <SelectInput source="role" choices={roleChoices} />
        <TextInput source="displayName" />
        <TextInput source="nickname" />
        <TextInput source="language" />
        <BooleanInput source="isPremium" />
        <BooleanInput source="isPrivate" />
      </SimpleForm>
    </Edit>
  );
}
