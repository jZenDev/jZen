import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import 'zen_icon_button.dart';

/// A page: an optional top bar over a body, Cupertino on Apple platforms and Material elsewhere.
///
/// It replaces the `Scaffold` + `AppBar` pair an app would otherwise write per screen. On iOS and
/// macOS that pair is a Material bar over Cupertino controls; here the bar is a
/// `CupertinoNavigationBar` over a `CupertinoPageScaffold`, chosen on [zenIsApplePlatform] so the
/// other idiom is tree-shaken.
///
/// * **One widget, not a pair.** The bar's contents ([title], [leading], [actions]) are
///   parameters of the page, so a screen cannot have a bar from one idiom and a body from the
///   other. The bar is drawn only when one of those is present.
/// * **The title is a heading.** It is the page's name for a screen reader on both idioms.
/// * **Back is a [ZenIconButton], with the platform's own arrow.** Pass [onBack] for an app that
///   routes on state rather than the `Navigator`; otherwise, when the page sits on a route that
///   can pop, the bar shows one that pops it. It is named by the platform's own "Back", with the
///   framework's focus ring and 48 px target. [automaticallyImplyLeading] false suppresses the
///   implied one, and [leading] replaces either. [actions] should be [ZenIconButton]s too.
/// * **Colour** follows the theme's `ColorScheme` (surface and on-surface; primary for the
///   buttons on Apple). [backgroundColor] and [foregroundColor] override the page and the bar's
///   title and icons, as an app's brand does.
/// * **Navigation is not in here.** `ZenNavigation` owns the shell (tabs, rail, sidebar); a page
///   sits in its body and brings its own bar, so the two compose without either knowing about the
///   other.
///
/// A [ZenPageScaffold] needs the `MaterialApp` an app already has: the Cupertino branch hosts the
/// bar in a transparent `Material`, and the body in another below the page's colour, so stock
/// widgets that need one (`ListTile`, `Chip`, a `PopupMenuButton` among the [actions]) work as they
/// do under a Material `Scaffold`: a tappable `ListTile` shows its ink.
class ZenPageScaffold extends StatelessWidget {
  /// Creates a page showing [body], under a bar when [title], [leading] or [actions] is given.
  const ZenPageScaffold({
    required this.body,
    this.title,
    this.leading,
    this.onBack,
    this.actions = const <Widget>[],
    this.automaticallyImplyLeading = true,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  /// The page's content, below the bar.
  final Widget body;

  /// The page's name, shown in the bar and announced as a heading.
  final String? title;

  /// A control at the bar's leading edge, replacing any back button; most pages want [onBack].
  final Widget? leading;

  /// Called by the back button this page shows when [leading] is null; null leaves the button to
  /// the implied pop.
  final VoidCallback? onBack;

  /// Controls at the bar's trailing edge, in order; normally [ZenIconButton]s.
  final List<Widget> actions;

  /// Whether a page with no [leading] and no [onBack] gets a back button that pops its route.
  final bool automaticallyImplyLeading;

  /// The page and bar colour; null is the theme's surface.
  final Color? backgroundColor;

  /// The colour of the bar's title and icons; null is the theme's on-surface (primary for the
  /// buttons on Apple).
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return zenIsApplePlatform
        ? buildCupertinoPageScaffold(context, this)
        : buildMaterialPageScaffold(context, this);
  }
}

/// The page's [ZenPageScaffold.leading], or the implied back button, or null for none.
Widget? _leadingOf(BuildContext context, ZenPageScaffold page, IconData backIcon) {
  if (page.leading != null) return page.leading;
  final VoidCallback? onBack = page.onBack;
  if (onBack == null) {
    final bool canPop = ModalRoute.of(context)?.canPop ?? false;
    if (!page.automaticallyImplyLeading || !canPop) return null;
  }
  return ZenIconButton(
    icon: backIcon,
    label: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: onBack ?? () => Navigator.maybePop(context),
  );
}

/// The title text, or null when the page has none. Both stock bars already mark their title as a
/// heading; wrapping it again would announce two.
Widget? _titleOf(ZenPageScaffold page, [TextStyle? style]) {
  final String? title = page.title;
  if (title == null) return null;
  return Text(title, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
}

/// The Material page. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialPageScaffold(BuildContext context, ZenPageScaffold page) {
  final Widget? leading = _leadingOf(context, page, Icons.arrow_back);
  final bool bar = page.title != null || leading != null || page.actions.isNotEmpty;
  return Scaffold(
    backgroundColor: page.backgroundColor,
    appBar: bar
        ? AppBar(
            // The bar's own back button has no focus ring; the framework's does.
            automaticallyImplyLeading: false,
            leading: leading,
            title: _titleOf(page),
            actions: page.actions,
            backgroundColor: page.backgroundColor,
            foregroundColor: page.foregroundColor,
          )
        : null,
    body: page.body,
  );
}

/// The Cupertino page; see [buildMaterialPageScaffold].
Widget buildCupertinoPageScaffold(BuildContext context, ZenPageScaffold page) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final Widget? leading = _leadingOf(context, page, CupertinoIcons.back);
  final bool bar = page.title != null || leading != null || page.actions.isNotEmpty;

  // An opaque bar, so the body is laid out below it: a translucent one lets the body scroll
  // underneath and hands it a top padding that a plain `Center` does not honour.
  final Color background = (page.backgroundColor ?? scheme.surface).withValues(alpha: 1);
  final Color title = page.foregroundColor ?? scheme.onSurface;
  final Color buttons = page.foregroundColor ?? scheme.primary;

  Widget tinted(Widget child) => IconTheme(
    data: IconThemeData(color: buttons),
    child: child,
  );

  return Material(
    type: MaterialType.transparency,
    child: CupertinoPageScaffold(
      backgroundColor: background,
      navigationBar: bar
          ? CupertinoNavigationBar(
              automaticallyImplyLeading: false,
              backgroundColor: background,
              leading: leading == null ? null : tinted(leading),
              middle: _titleOf(
                page,
                CupertinoTheme.of(context).textTheme.navTitleTextStyle.copyWith(color: title),
              ),
              trailing: page.actions.isEmpty
                  ? null
                  : tinted(Row(mainAxisSize: MainAxisSize.min, children: page.actions)),
            )
          : null,
      // A second Material, under the scaffold's coloured box. Ink paints on the nearest Material
      // above it, and `ListTile` refuses (in debug) to sit under a coloured box between it and
      // that Material: the outer one alone left the tile's ink and colour painted beneath the box.
      child: Material(type: MaterialType.transparency, child: page.body),
    ),
  );
}
