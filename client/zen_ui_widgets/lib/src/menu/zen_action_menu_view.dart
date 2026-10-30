import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'zen_action_menu.dart';

/// Builds one idiom's menu: a trigger that opens [MenuController] `controller` over `actions`.
///
/// [buildMaterialActionMenu] and [buildCupertinoActionMenu] are the two implementations; the
/// optional arguments are the behaviour [ZenActionMenuView] adds around either.
typedef ZenActionMenuBuilder =
    Widget Function(
      BuildContext context,
      String label,
      IconData icon,
      List<ZenMenuAction> actions,
      MenuController controller,
      FocusNode focusNode, {
      List<FocusNode>? itemNodes,
      VoidCallback? onOpen,
      VoidCallback? onArrowDown,
    });

/// The behaviour every `ZenActionMenu` shares, around the idiom [builder] supplies: focus moving
/// into the menu when it is opened from the keyboard, and one focus node per action.
///
/// It exists apart from `ZenActionMenu` so the package's tests can run it with either idiom's
/// builder, since a compile-time build reaches only one. Internal to the package: not exported.
class ZenActionMenuView extends StatefulWidget {
  /// Creates the menu with [builder]'s idiom.
  const ZenActionMenuView({
    required this.label,
    required this.icon,
    required this.actions,
    required this.builder,
    super.key,
  });

  /// The trigger's accessible name and tooltip.
  final String label;

  /// The trigger's glyph.
  final IconData icon;

  /// The menu's entries, in order.
  final List<ZenMenuAction> actions;

  /// The idiom to draw.
  final ZenActionMenuBuilder builder;

  @override
  State<ZenActionMenuView> createState() => _ZenActionMenuViewState();
}

class _ZenActionMenuViewState extends State<ZenActionMenuView> {
  final MenuController _controller = MenuController();
  final FocusNode _trigger = FocusNode(debugLabel: 'ZenActionMenu trigger');
  final List<FocusNode> _items = <FocusNode>[];

  /// The keys whose press opens the menu from the keyboard.
  static final Set<LogicalKeyboardKey> _openKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.arrowDown,
  };

  @override
  void dispose() {
    _trigger.dispose();
    for (final FocusNode node in _items) {
      node.dispose();
    }
    super.dispose();
  }

  /// One focus node per action, kept in step with the list.
  List<FocusNode> _nodes() {
    while (_items.length < widget.actions.length) {
      _items.add(FocusNode(debugLabel: 'ZenActionMenu item ${_items.length}'));
    }
    while (_items.length > widget.actions.length) {
      _items.removeLast().dispose();
    }
    return _items;
  }

  /// Puts focus on the first action that can be chosen, once the menu is on screen.
  void _focusFirst() {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      for (int i = 0; i < widget.actions.length; i++) {
        if (widget.actions[i].onPressed != null) {
          _items[i].requestFocus();
          return;
        }
      }
    });
  }

  /// A menu opened with the keyboard hands focus to its first action, so the arrow keys move
  /// through the menu rather than the page behind it; one opened with a pointer does not draw a
  /// focus highlight nobody asked for.
  void _onOpen() {
    if (HardwareKeyboard.instance.logicalKeysPressed.any(_openKeys.contains)) _focusFirst();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      widget.label,
      widget.icon,
      widget.actions,
      _controller,
      _trigger,
      itemNodes: _nodes(),
      onOpen: _onOpen,
      onArrowDown: _focusFirst,
    );
  }
}
