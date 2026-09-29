import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";
import indexHtml from "../../index.html?raw";

// jsdom starts from a blank document. The page language and title are the shipped index.html's
// (WCAG 3.1.1 and 2.4.2), so the axe run checks those, and fails if index.html ever loses them.
const shipped = new DOMParser().parseFromString(indexHtml, "text/html");
document.documentElement.lang = shipped.documentElement.lang;
document.title = shipped.title;

// jsdom implements neither; react-admin's responsive layout calls matchMedia on every render.
// "Not matched" is a desktop-width, light-mode, full-motion browser.
window.matchMedia ??= (query: string) =>
  ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }) as MediaQueryList;

globalThis.ResizeObserver ??= class {
  observe() {}
  unobserve() {}
  disconnect() {}
};

afterEach(() => {
  cleanup();
  window.location.hash = "";
  localStorage.clear();
});
