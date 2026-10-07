# Changelog

All notable changes to this package will be documented in this file.

## Unreleased

- `ZenButton`, `ZenSwitchRow`, `ZenSegmentedControl`, `ZenSelect`, `ZenDateField`,
  `ZenDateRangeField`, `ZenAmountField`, `ZenAmountRangeField` (with `normalizeAmount`,
  `parseAmount`, `ZenAmountInputFormatter`), each Cupertino on Apple platforms and Material
  elsewhere, built to WCAG 2.2 AA (one announcement per control, visible focus, contrast).
- `ZenTextField` (label, validator, error, obscure text, input formatters; no trailing-widget slot) and
  `ZenProgressIndicator`, both Cupertino on Apple platforms. `ZenAmountField` is now built on
  `ZenTextField`, so it is Cupertino on iOS and macOS too (it was Material everywhere), and
  `ZenButton`'s spinner is a `ZenProgressIndicator`.
- `FocusRing` moved here from `zen_ui_navigation` and is exported; new `FocusRing.wrapping`.
- `ZenWidgetsLocalizations` (`en`, `uk`) and `zenWidgetsLocaleDelegate` for the controls' strings.

## 0.1.0

- Initial release: `showAdaptivePresentation`, a sheet on native mobile and a dialog on desktop
  and web, Cupertino on iOS and macOS and Material elsewhere.
