import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:zen_core/zen_core.dart';

import 'button/zen_icon_button.dart';

/// Color treatment for a mobile swipe action.
enum ZenListItemActionVariant { standard, destructive }

/// An action supplied by the owner of a [ZenListItemActions] row.
class ZenListItemAction {
  const ZenListItemAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.variant = ZenListItemActionVariant.standard,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Selects the theme colors for the mobile swipe background.
  final ZenListItemActionVariant variant;
}

/// Adapts a list row's actions to the platform. The caller owns the row, actions,
/// and any confirmation needed before a destructive action.
///
/// Desktop shows actions continuously. Web reveals them on hover or focus; on
/// mobile the first action is invoked by a swipe towards the end, and the
/// second by a swipe towards the start. All enabled actions are available to
/// assistive technology. Give each item a stable key when reordering.
class ZenListItemActions extends StatefulWidget {
  const ZenListItemActions({
    required this.child,
    required this.actions,
    required this.showActionsLabel,
    required this.hideActionsLabel,
    super.key,
  });

  final Widget child;
  final List<ZenListItemAction> actions;
  final String showActionsLabel;
  final String hideActionsLabel;

  @override
  State<ZenListItemActions> createState() => _ZenListItemActionsState();
}

class _ZenListItemActionsState extends State<ZenListItemActions> {
  bool _expanded = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (zenIsMobile) {
      final startAction = widget.actions.isNotEmpty ? widget.actions[0] : null;
      final endAction = widget.actions.length > 1 ? widget.actions[1] : null;
      final startEnabled = startAction?.onPressed != null;
      final endEnabled = endAction?.onPressed != null;
      final row = Semantics(
        customSemanticsActions: {
          for (final action in widget.actions)
            if (action.onPressed != null)
              CustomSemanticsAction(label: action.label): action.onPressed!,
        },
        child: widget.child,
      );
      if (!startEnabled && !endEnabled) return row;
      Widget background(ZenListItemAction? action, bool isStart) {
        final colors = Theme.of(context).colorScheme;
        final destructive = action?.variant == ZenListItemActionVariant.destructive;
        final foreground = destructive ? colors.onErrorContainer : colors.onPrimaryContainer;
        final direction = Directionality.of(context);
        final iconDirection = isStart
            ? direction
            : direction == TextDirection.ltr
            ? TextDirection.rtl
            : TextDirection.ltr;
        return ColoredBox(
          color: destructive ? colors.errorContainer : colors.primaryContainer,
          child: Align(
            alignment: isStart ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    textDirection: iconDirection,
                    children: [
                      Icon(action?.icon, color: foreground),
                      const SizedBox(width: 8),
                      Text(action?.label ?? '', style: TextStyle(color: foreground)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return Dismissible(
        key: const ValueKey('zen-list-item-dismissible'),
        direction: startEnabled && endEnabled
            ? DismissDirection.horizontal
            : startEnabled
            ? DismissDirection.startToEnd
            : DismissDirection.endToStart,
        background: background(startAction, true),
        secondaryBackground: background(endAction, false),
        confirmDismiss: (direction) async {
          final action = direction == DismissDirection.startToEnd ? startAction : endAction;
          action?.onPressed?.call();
          return false;
        },
        child: row,
      );
    }
    final bool visible = zenIsDesktop || _expanded || (zenIsWeb && (_hovered || _focused));
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (value) => setState(() => _focused = value),
        child: Row(
          children: [
            Expanded(child: widget.child),
            AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: duration,
              child: ExcludeSemantics(
                excluding: !visible,
                child: ExcludeFocus(
                  excluding: !visible,
                  child: IgnorePointer(
                    ignoring: !visible,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final action in widget.actions)
                          ZenIconButton(
                            icon: action.icon,
                            label: action.label,
                            onPressed: action.onPressed,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (zenIsWeb && widget.actions.isNotEmpty)
              ZenIconButton(
                icon: _expanded ? Icons.close : Icons.more_horiz,
                label: _expanded ? widget.hideActionsLabel : widget.showActionsLabel,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
          ],
        ),
      ),
    );
  }
}
