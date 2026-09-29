import axe from "axe-core";
import { expect } from "vitest";

/**
 * The WCAG rule set the panel is held to: 2.0, 2.1 and 2.2 at levels A and AA. Best-practice
 * rules outside WCAG are left out on purpose — a gate should fail on what the standard requires,
 * not on axe's house style.
 */
const WCAG_AA = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

/**
 * Runs axe-core over the whole document (MUI renders menus and dialogs in portals outside the
 * app root) and fails with each violation's rule, help text and offending markup.
 *
 * jsdom has no layout, so axe reports colour contrast as "incomplete" here rather than passing or
 * failing it. Contrast is covered by the palette audit instead; see `accessibility.test.tsx`.
 */
export async function expectNoAxeViolations(): Promise<void> {
  const { violations } = await axe.run(document, {
    runOnly: { type: "tag", values: WCAG_AA },
  });
  const report = violations.map(
    (v) =>
      `${v.id}: ${v.help}\n${v.nodes.map((n) => `  ${n.html}`).join("\n")}`,
  );
  expect(report).toEqual([]);
}

type Rgba = [number, number, number, number];

/** Parses the colour notations MUI emits: `#rgb`, `#rrggbb`, `rgb()`, `rgba()`. */
export function parseColor(css: string): Rgba {
  const hex = css.match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/i);
  if (hex) {
    const h =
      hex[1].length === 3 ? [...hex[1]].map((c) => c + c).join("") : hex[1];
    return [0, 2, 4]
      .map((i) => parseInt(h.slice(i, i + 2), 16))
      .concat(1) as Rgba;
  }
  const fn = css.match(/^rgba?\(([^)]+)\)$/);
  if (fn) {
    const [r, g, b, a = "1"] = fn[1].split(/[\s,/]+/).filter(Boolean);
    return [Number(r), Number(g), Number(b), Number(a)];
  }
  throw new Error(`parseColor: unsupported colour "${css}"`);
}

/** WCAG contrast of [fg] drawn over the opaque [bg], compositing a translucent [fg] first. */
export function contrast(fg: string, bg: string): number {
  const [br, bgg, bb, ba] = parseColor(bg);
  if (ba !== 1) throw new Error(`contrast: background "${bg}" is not opaque`);
  const [fr, fgg, fb, fa] = parseColor(fg);
  const over = (f: number, b: number) => f * fa + b * (1 - fa);
  const luminance = (rgb: number[]) => {
    const [r, g, b] = rgb.map((c) => {
      const s = c / 255;
      return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const l1 = luminance([over(fr, br), over(fgg, bgg), over(fb, bb)]);
  const l2 = luminance([br, bgg, bb]);
  return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
}
