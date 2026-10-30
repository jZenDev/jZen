---
name: create-zen-widget
description: Create or change a reusable Zen UI widget in client/zen_ui_widgets. Use for framework controls and their platform behavior, accessibility, tests, exports and consumer documentation; use use-zen-ui for composing application screens.
---

# Create a Zen UI widget

Read `client/zen_ui_widgets/README.md`, the existing related control and
`docs/architecture/STANDARDS.md` (client UI, accessibility and widget files). Reuse an existing
control when it meets the need; put generic controls in `zen_ui_widgets`, not in an app.
The consumer supplies localized content and callbacks; the framework owns interaction and focus.

- Select platform idioms with `zen_core` compile-time constants, respecting existing exceptions
  such as iOS-only wheel pickers. Keep the Material path for web, Windows, Linux and Android.
  Do not introduce runtime client configuration.
- One widget class per snake_case file; a StatefulWidget stays with its own State. Group related
  files in a family folder. Preserve exports and expose only the intended public API.
- Make the control accessible: one meaningful semantics node, correct state and disabled behavior,
  keyboard activation and visible `FocusRing`, suitable target size, contrast, and reflow with
  long localized labels at 200% text. Do not duplicate semantics or keyboard stops.
- Test both platform implementations directly, since a compile-time build reaches only one.
  Cover state changes, disabled state, semantics, keyboard/focus, narrow layout and relevant
  contrast using the helpers in `test/support/a11y.dart`. Test public platform selection too.
- For every exported widget, add a dedicated heading, consumer-facing explanation and Dart usage
  example to `client/zen_ui_widgets/README.md`; update changed behavior there in the same change.
  `task verify:ui-docs` checks their presence, not correctness. Review examples against the API.
- Run `task verify:ui-docs`, `task verify:widget-files`, the affected widget suites and, for new
  controls, `task test:client` and the package tests on Chrome. Demonstrate visible behavior on
  relevant targets when available and report any unverified platforms.

Use `use-zen-ui` for the consumer-facing widget table and the complete accessibility test bar.
