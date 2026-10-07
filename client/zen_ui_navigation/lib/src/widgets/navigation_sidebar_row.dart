import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../zen_navigation_item.dart';
import 'navigation_badge.dart';

/// One destination of the macOS sidebar: its icon (with the badge), its label, and a rounded
/// highlight when it is the selected one.
///
/// It is a single accessible node: "Inbox, 3 new, button, selected", then its position as a hint
/// ("2 of 5"). The icon and the badge add no words of their own (see [navigationBadge]), and a
/// merge keeps the row from being read as a stack of nested nodes of which only one responds.
///
/// Every row is its own tab stop; Enter and Space activate it through [ActivateIntent].
/// [FocusRing] sits inside the detector, which owns the focus node it reads.
class NavigationSidebarRow extends StatelessWidget {
  /// Creates the row for [item]; [position] is the localized "n of m" read after its name.
  const NavigationSidebarRow({
    required this.item,
    required this.selected,
    required this.position,
    required this.onPressed,
    super.key,
  });

  /// The destination this row stands for.
  final ZenNavigationItem item;

  /// Whether this destination is the one currently shown.
  final bool selected;

  /// Where this destination sits among the others, as the screen reader should say it.
  final String position;

  /// Called when the row is tapped, or activated from the keyboard.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // The theme's own pairs, so the text is as legible as the app's palette makes it in light and
    // in dark: onSecondaryContainer is defined to sit on secondaryContainer.
    final Color foreground = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    final TextStyle style = CupertinoTheme.of(context).textTheme.textStyle.copyWith(
      color: foreground,
      fontSize: 14,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        hint: position,
        child: FocusableActionDetector(
          // A sidebar row shows the arrow, not the hand: that is how a native one behaves.
          mouseCursor: SystemMouseCursors.basic,
          // Named here rather than left to the app's defaults: a web build maps Space but not
          // Enter to activation, leaving a keyboard user a row that only one of the two keys moves.
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (ActivateIntent _) {
                onPressed();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Padding(
              // The gap holds the ring (drawn 4 px outside the row) clear of the next row.
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: FocusRing(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected ? scheme.secondaryContainer : null,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 32),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: <Widget>[
                          IconTheme.merge(
                            data: IconThemeData(color: foreground, size: 18),
                            child: navigationBadge(item),
                          ),
                          const SizedBox(width: 10),
                          // Wraps rather than clips: at 200% text (WCAG SC 1.4.4) a long label
                          // grows the row instead of losing its end.
                          Expanded(child: Text(item.label, style: style)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
