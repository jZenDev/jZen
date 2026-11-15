import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// The app's light and dark themes: one seed colour, and the framework's page transitions
/// (ADR-061).
ThemeData demoLocalTheme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
  useMaterial3: true,
  pageTransitionsTheme: ZenPageTransitions.theme,
);
