// Conditional imports for platform-specific widgets
import 'package:zen_core/zen_core.dart';
import 'package:flutter/widgets.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show ZenPageWidthScope;

// Web keys on `dart.library.js_interop` (dart2js AND dart2wasm), not `dart.library.html`
// (dart2js only), which under Wasm would miss and fall through to the stub.
import './widgets/navigation_stub.dart'
    if (dart.library.js_interop) './widgets/navigation_web.dart'
    if (dart.library.io) './widgets/navigation_native.dart';
import 'zen_navigation_item.dart';

/// A navigation widget [ZenNavigation] that can be used to navigate between
/// different screens.
///
/// It is a builder pattern that allows you to create a navigation widget
/// with a builder function that returns a widget. It is platform adaptive
/// and will render different layouts based on the platform. On mobile it
/// applies 'overflow' behavior, meaning that if there are more than 4 items,
/// a 'more' button will be displayed, which will open a screen with the
/// remaining items. The 'more' label is customizable via [labelMore], and otherwise comes
/// from the typed, generated `NavigationLocalizations` resolved from the [BuildContext].
///
/// Example:
/// ```dart
/// final navigation = ZenNavigation(
///   items: [
///     ZenNavigationItem(
///       id: 'home',
///       label: 'Home',
///       icon: const Icon(Icons.home),
///       builder: (context) => const HomeScreen(),
///     ),
///   ],
///   selectedIndex: 0,
///   onItemSelected: (id) { // Handle navigation if needed },
/// );
/// ```
class ZenNavigation extends StatelessWidget {
  /// Creates a new [ZenNavigation].
  const ZenNavigation({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.items,
    super.key,
    this.onItemSelectedId,
    this.labelMore,
    this.contentMaxWidth,
    this.contentGutter = 16,
  }) : assert(
         contentMaxWidth == null || (contentMaxWidth > 0 && contentMaxWidth < double.infinity),
       ),
       assert(contentGutter >= 0 && contentGutter < double.infinity);

  /// The selected index of the navigation item.
  final int selectedIndex;

  /// The callback function that is called when a navigation item is selected.
  final ValueChanged<int> onItemSelected;

  /// The callback function that is called when a navigation item is selected.
  /// This callback provides the unique identifier of the selected item.
  final ValueChanged<String>? onItemSelectedId;

  /// The list of navigation items.
  final List<ZenNavigationItem> items;

  /// The label for the "more" button.
  /// If null, it comes from `NavigationLocalizations.of(context).more`.
  final String? labelMore;

  /// Default maximum width of page bodies, excluding the gutter. Null leaves them unconstrained.
  final double? contentMaxWidth;

  /// Minimum horizontal space on each side of a constrained page body.
  final double contentGutter;

  @override
  Widget build(BuildContext context) {
    // Expect ZEN_PLATFORM to be set
    assert(zenPlatform.isNotEmpty);
    // Forward to platform-specific implementation
    final Widget navigation = buildPlatformNavigation(
      context: context,
      selectedIndex: selectedIndex,
      onItemSelected: onItemSelected,
      onItemSelectedId: onItemSelectedId,
      items: items,
      labelMore: labelMore,
    );
    final double? width = contentMaxWidth;
    return width == null
        ? navigation
        : ZenPageWidthScope(maxWidth: width, gutter: contentGutter, child: navigation);
  }
}

/// typedef for platform factory
typedef PlatformNavigationBuilder =
    Widget Function({
      required BuildContext context,
      required int selectedIndex,
      required ValueChanged<int> onItemSelected,
      required List<ZenNavigationItem> items,
      ValueChanged<String>? onItemSelectedId,
      String? labelMore,
    });
