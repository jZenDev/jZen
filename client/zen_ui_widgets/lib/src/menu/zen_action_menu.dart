import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';

import '../button/zen_icon_button.dart';
import 'zen_action_menu_view.dart';

/// One entry of a [ZenActionMenu]: a labelled action with an optional icon.
class ZenMenuAction {
  /// Creates an action shown as [label] that runs [onPressed].
  const ZenMenuAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.destructive = false,
  });

  /// The action's text, and its accessible name.
  final String label;

  /// Run once when the action is chosen, after the menu has closed. Null disables the action:
  /// it stays in the menu, announced as disabled, and cannot be chosen.
  final VoidCallback? onPressed;

  /// An optional glyph shown beside the label; decorative, never the name.
  final IconData? icon;

  /// Marks the action as the current choice of a set (the language in use), with a check mark
  /// and a "selected" announcement. The menu does not move it: the app owns which is current.
  final bool selected;

  /// Draws the action as one that deletes or cannot be undone: red on Apple platforms.
  final bool destructive;
}

/// An icon button that opens a menu of actions beneath it: a Material menu elsewhere, a
/// Cupertino menu on Apple platforms.
///
/// The trigger is a `ZenIconButton` named by [label] — "Language, button, collapsed" — and the
/// menu holds the [actions] in order. Choosing an action closes the menu and runs its callback
/// once; Escape, a tap outside, or focus leaving closes it without running anything. A disabled
/// action ([ZenMenuAction.onPressed] null) is shown and announced as disabled, is skipped by
/// the keyboard and never fires. Focus returns to the trigger when the menu closes.
///
/// Enter, Space or a click opens the menu; the arrow keys move through the items, Home and End
/// jump to the first and last, Enter or Space chooses the focused one. The framework places the
/// menu beside the trigger and keeps it on screen, so it is not clipped in a narrow window; long
/// labels wrap rather than being cut off.
///
/// This is a menu of *actions*. To choose a value for a field use `ZenSelect`; for a handful of
/// exclusive options in the page use `ZenSegmentedControl`.
class ZenActionMenu extends StatelessWidget {
  /// Creates a menu opened by an icon button named [label].
  const ZenActionMenu({
    required this.label,
    required this.actions,
    this.icon,
    super.key,
  }) : assert(actions.length > 0, 'a menu offers at least one action');

  /// The trigger's accessible name and tooltip, such as "Language" or "More actions".
  final String label;

  /// The menu's entries, in order.
  final List<ZenMenuAction> actions;

  /// The trigger's glyph; the platform's "more" glyph — three dots, vertical on Material, in a row
  /// on Apple platforms — when null.
  final IconData? icon;

  @override
  Widget build(BuildContext context) => ZenActionMenuView(
    label: label,
    icon: icon ?? (zenIsApplePlatform ? CupertinoIcons.ellipsis : Icons.more_vert),
    actions: actions,
    builder: zenIsApplePlatform ? buildCupertinoActionMenu : buildMaterialActionMenu,
  );
}

/// The trigger both idioms share: a labelled icon button that toggles the menu and says whether it
/// is open.
Widget _trigger(
  String label,
  IconData icon,
  MenuController controller,
  FocusNode focusNode,
  VoidCallback? onArrowDown,
) {
  // Merged, so "expanded" is a state of the button itself rather than of a node around it.
  return MergeSemantics(
    child: Semantics(
      expanded: controller.isOpen,
      // Down Arrow on the trigger opens the menu, or moves into it when it is already open.
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowDown): () {
            if (!controller.isOpen) controller.open();
            onArrowDown?.call();
          },
        },
        child: ZenIconButton(
          icon: icon,
          label: label,
          focusNode: focusNode,
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    ),
  );
}

/// Space an item spends on its padding, an icon, and the least a label may be squeezed to.
const double _itemChrome = 32;
const double _itemIcon = 40;
const double _itemMinText = 80;

/// The Material menu. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialActionMenu(
  BuildContext context,
  String label,
  IconData icon,
  List<ZenMenuAction> actions,
  MenuController controller,
  FocusNode focusNode, {
  List<FocusNode>? itemNodes,
  VoidCallback? onOpen,
  VoidCallback? onArrowDown,
}) {
  // Never wider than the screen it opens on: the menu is capped, and the labels inside it are
  // capped to what is left after the item's padding and icons, so a long one wraps.
  final double maxWidth = MediaQuery.sizeOf(context).width - 16;
  final Color error = Theme.of(context).colorScheme.error;
  return MenuAnchor(
    controller: controller,
    childFocusNode: focusNode,
    onOpen: onOpen,
    style: MenuStyle(maximumSize: WidgetStatePropertyAll<Size>(Size(maxWidth, double.infinity))),
    menuChildren: <Widget>[
      for (int i = 0; i < actions.length; i++)
        // Merged, so "selected" belongs to the item's own node.
        MergeSemantics(
          child: Semantics(
            selected: actions[i].selected,
            child: MenuItemButton(
              focusNode: itemNodes?[i],
              onPressed: actions[i].onPressed,
              leadingIcon: actions[i].icon == null ? null : Icon(actions[i].icon),
              trailingIcon: actions[i].selected ? const Icon(Icons.check) : null,
              style: actions[i].destructive
                  ? MenuItemButton.styleFrom(foregroundColor: error)
                  : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      (maxWidth -
                              _itemChrome -
                              (actions[i].icon == null ? 0 : _itemIcon) -
                              (actions[i].selected ? _itemIcon : 0))
                          .clamp(_itemMinText, double.infinity),
                ),
                child: Text(actions[i].label),
              ),
            ),
          ),
        ),
    ],
    builder: (BuildContext context, MenuController c, Widget? child) =>
        _trigger(label, icon, c, focusNode, onArrowDown),
  );
}

/// The Cupertino menu; see [buildMaterialActionMenu].
Widget buildCupertinoActionMenu(
  BuildContext context,
  String label,
  IconData icon,
  List<ZenMenuAction> actions,
  MenuController controller,
  FocusNode focusNode, {
  List<FocusNode>? itemNodes,
  VoidCallback? onOpen,
  VoidCallback? onArrowDown,
}) {
  final double maxWidth = MediaQuery.sizeOf(context).width - 16;
  final Color error = Theme.of(context).colorScheme.error;
  return CupertinoMenuAnchor(
    controller: controller,
    childFocusNode: focusNode,
    onOpen: onOpen,
    constraints: BoxConstraints(maxWidth: maxWidth),
    constrainCrossAxis: true,
    menuChildren: <Widget>[
      for (int i = 0; i < actions.length; i++)
        MergeSemantics(
          child: Semantics(
            selected: actions[i].selected,
            child: CupertinoMenuItem(
              focusNode: itemNodes?[i],
              onPressed: actions[i].onPressed,
              isDestructiveAction: actions[i].destructive,
              leading: actions[i].icon == null ? null : Icon(actions[i].icon),
              trailing: actions[i].selected ? const Icon(CupertinoIcons.checkmark_alt) : null,
              // The system red of a destructive item is under 4.5:1 on a light menu; the
              // theme's error colour is chosen to clear it.
              child: Text(
                actions[i].label,
                style: actions[i].destructive ? TextStyle(color: error) : null,
              ),
            ),
          ),
        ),
    ],
    builder: (BuildContext context, MenuController c, Widget? child) =>
        _trigger(label, icon, c, focusNode, onArrowDown),
  );
}
