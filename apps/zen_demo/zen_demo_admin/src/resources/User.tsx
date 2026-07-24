import {
  BooleanField,
  BooleanInput,
  Datagrid,
  DateField,
  Edit,
  EmailField,
  List,
  SelectInput,
  Show,
  SimpleForm,
  SimpleShowLayout,
  TextField,
  TextInput,
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
      <Datagrid rowClick="show">
        <EmailField source="email" />
        <TextField source="displayName" />
        <TextField source="role" />
        <BooleanField source="isPremium" />
        <DateField source="createdAtMs" label="Created" showTime />
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
      <SimpleForm>
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
