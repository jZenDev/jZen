import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import 'button/zen_icon_button.dart';

/// An action supplied by the owner of a [ZenListItemActions] row.
class ZenListItemAction {
  const ZenListItemAction({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
}

/// Adapts a list row's actions to the platform. The caller owns the row, actions,
/// and any confirmation needed before a destructive action.
///
/// Desktop shows actions continuously. Web reveals them on hover or focus; on
/// mobile a swipe reveals them. The labeled toggle also makes actions available
/// without a swipe or hover. Give each list item a stable key when reordering.
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
    final bool desktop = zenIsDesktop;
    final bool visible = desktop || _expanded || (zenIsWeb && (_hovered || _focused));
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (value) => setState(() => _focused = value),
        child: GestureDetector(
          onHorizontalDragEnd: zenIsMobile
              ? (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() > 100) {
                    final isRtl = Directionality.of(context) == TextDirection.rtl;
                    setState(() => _expanded = isRtl ? velocity > 0 : velocity < 0);
                  }
                }
              : null,
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
              if (!desktop && widget.actions.isNotEmpty)
                ZenIconButton(
                  icon: _expanded ? Icons.close : Icons.more_horiz,
                  label: _expanded ? widget.hideActionsLabel : widget.showActionsLabel,
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
