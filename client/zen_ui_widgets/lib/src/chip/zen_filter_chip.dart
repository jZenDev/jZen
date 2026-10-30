import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import '../adaptive_ink_well.dart';
import '../focus_ring.dart';

/// A compact labelled choice that is switched on and off **independently of its neighbours** — a
/// filter or a tag. Several can be selected at once; selecting one never changes another. A
/// Material filter chip elsewhere, a rounded Cupertino capsule on Apple platforms.
///
/// This is a *filter* chip and nothing else: it holds a selected state the app owns. An action
/// that merely does something (a suggestion, "Add tag") is a `ZenButton`, and a single choice
/// among several is a `ZenRadioGroup` or `ZenSegmentedControl`; each says what it is to a screen
/// reader, which a chip pretending to be them would not.
///
/// Selection is shown by a leading check mark and a filled, outlined capsule, never by colour
/// alone, and announced as "Groceries, button, selected". The chip is one control with one tab
/// stop, activated by Space or Enter, ringed by a [FocusRing] while focused. A long label wraps
/// onto further lines instead of being cut off, so a chip stays usable at 200% text on a narrow
/// screen. Lay several out in a `Wrap` so they flow onto new lines.
class ZenFilterChip extends StatelessWidget {
  /// Creates a chip labelled [label].
  const ZenFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The chip's text, and its accessible name.
  final String label;

  /// Whether the filter is on.
  final bool selected;

  /// Called with the value the user asks for — the opposite of [selected]; null disables the chip.
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    return zenIsApplePlatform
        ? buildCupertinoFilterChip(context, label, selected, onSelected)
        : buildMaterialFilterChip(context, label, selected, onSelected);
  }
}

/// The Material chip. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialFilterChip(
  BuildContext context,
  String label,
  bool selected,
  ValueChanged<bool>? onSelected,
) {
  return FocusRing.wrapping(
    child: FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: true,
      onSelected: onSelected,
    ),
  );
}

/// The Cupertino capsule; see [buildMaterialFilterChip].
///
/// Flutter has no Cupertino chip, so this draws one: an ink-free tap target, at least 44 points
/// tall, around a capsule that fills and gains a check mark when selected.
Widget buildCupertinoFilterChip(
  BuildContext context,
  String label,
  bool selected,
  ValueChanged<bool>? onSelected,
) {
  final bool enabled = onSelected != null;
  final ThemeData theme = Theme.of(context);
  final ColorScheme colors = theme.colorScheme;
  final Color foreground = !enabled
      ? theme.disabledColor
      : (selected ? colors.onSecondaryContainer : colors.onSurface);
  final Color border = !enabled
      ? theme.disabledColor
      : (selected ? colors.onSecondaryContainer : colors.outline);
  void toggle() => onSelected?.call(!selected);

  return FocusRing.wrapping(
    child: Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      focusable: enabled,
      onTap: enabled ? toggle : null,
      child: buildCupertinoInkWell(
        onTap: enabled ? toggle : null,
        borderRadius: BorderRadius.circular(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected && enabled ? colors.secondaryContainer : null,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (selected) ...<Widget>[
                      Icon(CupertinoIcons.checkmark_alt, size: 16, color: foreground),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(color: foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
