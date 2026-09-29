/// Shared adaptive widgets for jZen applications: the chrome that is neither navigation
/// (`zen_ui_navigation`) nor identity (`zen_ui_identity`).
///
/// Every widget here renders Cupertino on Apple platforms (iOS and macOS) and Material
/// everywhere else, chosen by compile-time constants from `zen_core` so each build tree-shakes
/// the idiom it never uses.
///
/// Today that is [showAdaptivePresentation], a form/detail overlay that is a sheet on native
/// mobile and a dialog on desktop and web.
library;

export 'src/adaptive_presentation.dart';
