import { darkTheme, lightTheme } from "@jzen/admin-core";
import { createTheme, type Theme } from "@mui/material/styles";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { AuthProvider, DataProvider, RaThemeOptions } from "react-admin";
import { describe, expect, it, vi } from "vitest";
import { App } from "./App";
import type { AdminUser } from "./resources/User";
import { contrast, expectNoAxeViolations } from "./test/a11y";

/**
 * The admin panel held to WCAG 2.2 AA (STANDARDS "Accessibility"): axe-core over every view,
 * a keyboard-only walkthrough of the login form and of the path from the user list into a record,
 * focus management on navigation, and a contrast audit of both shipped palettes.
 *
 * It renders the real `App` — the scaffold's layout and themes, this app's resources — with
 * in-memory providers in place of the live API.
 */

const users: AdminUser[] = [
  {
    id: "u1",
    email: "ada@example.com",
    displayName: "Ada",
    nickname: "ada",
    role: "admin",
    language: "en",
    isPremium: true,
    isPrivate: false,
    emailVerified: true,
    createdAtMs: 1_700_000_000_000,
    lastLoginAtMs: 1_700_000_100_000,
  },
  {
    id: "u2",
    email: "grace@example.com",
    displayName: "Grace",
    role: "user",
    createdAtMs: 1_700_000_200_000,
  },
];

const dataProvider = {
  getList: async () => ({ data: users, total: users.length }),
  getOne: async (_: string, { id }: { id: string }) => ({
    data: users.find((u) => u.id === id),
  }),
  getMany: async () => ({ data: users }),
  getManyReference: async () => ({ data: [], total: 0 }),
  update: async (_: string, { data }: { data: AdminUser }) => ({ data }),
  updateMany: async () => ({ data: [] }),
  create: async (_: string, { data }: { data: AdminUser }) => ({ data }),
  delete: async (_: string, { previousData }: { previousData: AdminUser }) => ({
    data: previousData,
  }),
  deleteMany: async () => ({ data: [] }),
} as unknown as DataProvider;

function authProvider(signedIn: boolean) {
  return {
    login: vi.fn(async () => {}),
    logout: async () => {},
    checkAuth: async () => {
      if (!signedIn) throw new Error("signed out");
    },
    checkError: async () => {},
    getPermissions: async () => undefined,
    getIdentity: async () => ({ id: "admin", fullName: "Admin" }),
  } satisfies AuthProvider;
}

function renderAt(hash: string, auth = authProvider(true)) {
  window.location.hash = hash;
  render(<App dataProvider={dataProvider} authProvider={auth} />);
  return auth;
}

/**
 * Presses Tab until [target] holds focus, failing after [limit] presses. Returns how many it took,
 * so a test can also say the target was reached *before* something else.
 */
async function tabTo(
  user: ReturnType<typeof userEvent.setup>,
  target: Element,
  limit = 60,
): Promise<number> {
  for (let presses = 1; presses <= limit; presses++) {
    await user.tab();
    if (document.activeElement === target) return presses;
  }
  throw new Error(`Tab never reached ${target.outerHTML.slice(0, 120)}`);
}

describe("login page", () => {
  it("has no WCAG A/AA violations", async () => {
    renderAt("#/login", authProvider(false));
    await screen.findByLabelText(/email/i);
    await expectNoAxeViolations();
  });

  it("is operable by keyboard alone, in reading order", async () => {
    const user = userEvent.setup();
    const auth = renderAt("#/login", authProvider(false));
    const email = await screen.findByLabelText(/email/i);
    const password = screen.getByLabelText(/password/i, { selector: "input" });
    const submit = screen.getByRole("button", { name: /sign in/i });

    // The form opens with focus in its first field, and Tab walks it in reading order.
    await waitFor(() => expect(document.activeElement).toBe(email));
    await user.keyboard("ada@example.com");
    expect(await tabTo(user, password, 1)).toBe(1);
    await user.keyboard("secret");
    await tabTo(user, submit, 3);

    // Enter in a field submits, as it does in any browser form.
    password.focus();
    await user.keyboard("{Enter}");
    await waitFor(() =>
      expect(auth.login).toHaveBeenCalledWith({
        username: "ada@example.com",
        password: "secret",
      }),
    );
  });
});

describe("users", () => {
  it("list, show and edit have no WCAG A/AA violations", async () => {
    renderAt("#/users");
    await screen.findByText("ada@example.com");
    await expectNoAxeViolations();

    window.location.hash = "#/users/u1/show";
    await screen.findByText("Last login");
    await expectNoAxeViolations();

    window.location.hash = "#/users/u1";
    await screen.findByRole("button", { name: /save/i });
    await expectNoAxeViolations();
  });

  it("a keyboard user can open a record from the list, and focus follows", async () => {
    const user = userEvent.setup();
    renderAt("#/users");
    await screen.findByText("ada@example.com");

    // Row click is mouse-only; the Show and Edit buttons are the keyboard's way in.
    const [show] = screen.getAllByRole("link", { name: /show/i });
    await tabTo(user, show);
    await user.keyboard("{Enter}");
    await screen.findByText("Last login");

    // The Show button went away with the list; focus must land on the new view, not <body>.
    const main = document.getElementById("main-content");
    await waitFor(() => expect(document.activeElement).toBe(main));

    // From there the edit form is reachable too, and every control in it.
    const edit = await screen.findByRole("link", { name: /edit/i });
    await tabTo(user, edit);
    await user.keyboard("{Enter}");
    const save = await screen.findByRole("button", { name: /save/i });
    await waitFor(() => expect(document.activeElement).toBe(main));

    const controls = [
      screen.getByRole("combobox", { name: /role/i }),
      screen.getByRole("textbox", { name: /display name/i }),
      screen.getByRole("textbox", { name: /nickname/i }),
      screen.getByRole("textbox", { name: /language/i }),
      screen.getByRole("switch", { name: /is premium/i }),
      screen.getByRole("switch", { name: /is private/i }),
    ];
    for (const control of controls) await tabTo(user, control, 20);
    // Save is disabled until the form is dirty; change a field and it becomes reachable.
    await user.keyboard(" ");
    await waitFor(() =>
      expect((save as HTMLButtonElement).disabled).toBe(false),
    );
    await tabTo(user, save, 20);
  });
});

describe("contrast of the shipped palettes", () => {
  const AA_TEXT = 4.5;
  const palettes: [string, RaThemeOptions][] = [
    ["light", lightTheme],
    ["dark", darkTheme],
  ];

  for (const [name, options] of palettes) {
    const theme: Theme = createTheme(options);
    const { palette } = theme;

    it(`${name}: text, links, buttons and errors meet AA`, () => {
      const pairs: [string, string, string][] = [
        [
          "text.primary on default",
          palette.text.primary,
          palette.background.default,
        ],
        [
          "text.primary on paper",
          palette.text.primary,
          palette.background.paper,
        ],
        [
          "text.secondary on default",
          palette.text.secondary,
          palette.background.default,
        ],
        [
          "text.secondary on paper",
          palette.text.secondary,
          palette.background.paper,
        ],
        // Text buttons (Show, Edit) and links are drawn in primary on paper.
        ["primary on paper", palette.primary.main, palette.background.paper],
        // Contained buttons (Save) and the skip link.
        [
          "primary.contrastText on primary",
          palette.primary.contrastText,
          palette.primary.main,
        ],
        // Validation messages under a field.
        ["error on paper", palette.error.main, palette.background.paper],
      ];
      if (palette.mode === "light") {
        // The app bar, and the page title it carries.
        pairs.push([
          "secondary.contrastText on secondary",
          palette.secondary.contrastText,
          palette.secondary.main,
        ]);
      }
      const failing = pairs
        .map(([pair, fg, bg]) => [pair, contrast(fg, bg)] as const)
        .filter(([, ratio]) => ratio < AA_TEXT)
        .map(([pair, ratio]) => `${pair}: ${ratio.toFixed(2)}:1`);
      expect(failing).toEqual([]);
    });

    it(`${name}: the skip link is legible when it appears`, () => {
      const override = theme.components?.RaSkipNavigationButton?.styleOverrides
        ?.root as (props: { theme: Theme }) => {
        color: string;
        backgroundColor: string;
      };
      const { color, backgroundColor } = override({ theme });
      expect(contrast(color, backgroundColor)).toBeGreaterThanOrEqual(AA_TEXT);
    });
  }
});
