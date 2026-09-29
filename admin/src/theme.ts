import {
  defaultDarkTheme,
  defaultLightTheme,
  type RaThemeOptions,
} from "react-admin";

/** The part of MUI's Theme the override reads; the scaffold reaches MUI only through react-admin. */
type PrimaryPalette = {
  palette: { primary: { main: string; dark: string; contrastText: string } };
};

/**
 * react-admin's default light and dark themes, minus the two pairings in them that fail WCAG AA.
 *
 * - **The "Skip to content" link** — the first stop for a keyboard user, which lets them jump past
 *   the app bar and menu — is drawn in `primary.contrastText` on `background.default`: white on
 *   near-white in the light theme, near-black on dark grey in the dark one. About 1:1, so the link
 *   is invisible exactly when it is focused. Here it is the contained button it is, in
 *   `primary.contrastText` on `primary.main`, a pairing the palette already guarantees.
 * - **The light app bar** is `secondary.main` (#2196f3) under white text, 3.1:1, and the page
 *   title it carries is 20px regular — under the 24px that would let it pass at 3:1. Material's
 *   blue 800 keeps the hue at 5.8:1. The dark app bar is drawn on `background.paper` and passes.
 *
 * An app passes these as `lightTheme` / `darkTheme` to `<Admin>`; both ship because react-admin
 * follows the browser's `prefers-color-scheme`. `task test:admin` audits both palettes.
 */
function withAccessibleSkipLink(base: RaThemeOptions): RaThemeOptions {
  return {
    ...base,
    components: {
      ...base.components,
      RaSkipNavigationButton: {
        styleOverrides: {
          root: ({ theme }: { theme: PrimaryPalette }) => ({
            backgroundColor: theme.palette.primary.main,
            color: theme.palette.primary.contrastText,
            "&:hover": { backgroundColor: theme.palette.primary.dark },
          }),
        },
      },
    },
  };
}

export const lightTheme: RaThemeOptions = withAccessibleSkipLink({
  ...defaultLightTheme,
  palette: {
    ...defaultLightTheme.palette,
    secondary: {
      light: "#5e92f3",
      main: "#1565c0",
      dark: "#003c8f",
      contrastText: "#fff",
    },
  },
});
export const darkTheme: RaThemeOptions =
  withAccessibleSkipLink(defaultDarkTheme);
