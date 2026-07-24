import {
  Form,
  Login,
  PasswordInput,
  TextInput,
  useLogin,
  useNotify,
} from "react-admin";

/**
 * Login page for the jZen admin panel. A thin form over react-admin's `useLogin`, which delegates
 * to the auth provider (`POST {authBase}/login`). The email is passed as `username` - the field
 * name react-admin's auth contract expects - and mapped back to `email` in the auth provider.
 */
export function LoginPage() {
  const login = useLogin();
  const notify = useNotify();

  const submit = (values: Record<string, string>) => {
    login({ username: values.email, password: values.password }).catch(
      (error: unknown) => {
        const message = error instanceof Error ? error.message : "Login failed";
        notify(message, { type: "error" });
      },
    );
  };

  return (
    <Login>
      <Form onSubmit={submit as (values: unknown) => void}>
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 8,
            padding: 16,
          }}
        >
          <TextInput source="email" label="Email" type="email" autoFocus />
          <PasswordInput source="password" label="Password" />
          <button type="submit">Sign in</button>
        </div>
      </Form>
    </Login>
  );
}
