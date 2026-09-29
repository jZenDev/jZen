import { useEffect, useRef } from "react";
import { Layout as RaLayout, type LayoutProps, useLocation } from "react-admin";

/** The main content region react-admin's Layout renders, and its skip link targets. */
const MAIN_CONTENT_ID = "main-content";

/**
 * react-admin's Layout, plus focus management on navigation (WCAG 2.4.3 Focus Order).
 *
 * A route change here swaps the view without a page load, so the browser never resets focus. When
 * the control that navigated is unmounted with the old view — a row's Show button, a form's Save
 * button — focus falls to `<body>`: a screen reader announces nothing, and a keyboard user's next
 * Tab starts again from the top of the page. After every navigation this moves focus to the main
 * content region, the same target as react-admin's own skip link, so the new view is where the
 * user already is.
 */
export function Layout({ children, ...props }: LayoutProps) {
  return (
    <RaLayout {...props}>
      <FocusMainOnNavigate />
      {children}
    </RaLayout>
  );
}

function FocusMainOnNavigate() {
  const { pathname } = useLocation();
  const firstRender = useRef(true);

  useEffect(() => {
    // The first view is a page load, where the browser's own focus handling applies.
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    const main = document.getElementById(MAIN_CONTENT_ID);
    if (!main) {
      // react-admin's Layout always renders it; absent means the Layout changed underneath us.
      throw new Error(`Layout: no #${MAIN_CONTENT_ID} to move focus to`);
    }
    // -1: focusable by script, not a Tab stop of its own.
    main.setAttribute("tabindex", "-1");
    main.focus({ preventScroll: true });
  }, [pathname]);

  return null;
}
