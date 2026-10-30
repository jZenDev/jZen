import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import '../apple_row.dart';
import '../focus_ring.dart';

/// A labelled checkbox row for an independent selection, a consent or one item of a multiple
/// selection: the checkbox and the label side by side, the whole row one tap target. Cupertino
/// checkbox on Apple platforms, Material elsewhere.
///
/// The app owns [value]. A `true` or `false` value is a plain checkbox; a `null` value is the
/// **mixed** state — some, but not all, of a group the row stands for — drawn as a dash and
/// announced as "mixed". A tap always asks for a definite answer: a mixed or unchecked row
/// reports `true`, a checked row reports `false`. The control never cycles into mixed by itself,
/// because only the app knows what the group holds.
///
/// The row is **one control announced once** — "Accept terms, checkbox, checked" — with the label,
/// role and state on the node that takes focus and activates with Space. A [FocusRing] surrounds
/// the row while it holds keyboard focus.
class ZenCheckboxRow extends StatelessWidget {
  /// Creates a row labelled [label].
  const ZenCheckboxRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  /// What the checkbox stands for; also its accessible name.
  final String label;

  /// Whether the row is checked; null is the mixed state.
  final bool? value;

  /// Called with the value the user asks for; null disables the row.
  final ValueChanged<bool>? onChanged;

  /// Optional second line explaining the choice; read after the label.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return FocusRing.wrapping(
      child: zenIsApplePlatform
          ? buildCupertinoCheckboxRow(context, label, subtitle, value, onChanged)
          : buildMaterialCheckboxRow(context, label, subtitle, value, onChanged),
    );
  }
}

/// The Material row. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialCheckboxRow(
  BuildContext context,
  String label,
  String? subtitle,
  bool? value,
  ValueChanged<bool>? onChanged,
) {
  return CheckboxListTile(
    value: value,
    tristate: value == null,
    // The tile hands over its own next value, which for a mixed row would be `false`.
    onChanged: onChanged == null ? null : (bool? _) => onChanged(value != true),
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(label),
    subtitle: subtitle == null ? null : Text(subtitle),
  );
}

/// The Cupertino row; see [buildMaterialCheckboxRow].
///
/// A [CupertinoCheckbox] alone has no label and only the box is tappable, so the row is the
/// control: an ink-free tap target that asks for the opposite value, with the checkbox drawn
/// inside it but taken out of focus and hit testing so there is one tab stop and one node.
Widget buildCupertinoCheckboxRow(
  BuildContext context,
  String label,
  String? subtitle,
  bool? value,
  ValueChanged<bool>? onChanged,
) {
  final bool enabled = onChanged != null;
  void toggle() => onChanged?.call(value != true);

  return Semantics(
    container: true,
    excludeSemantics: true,
    enabled: enabled,
    checked: value ?? false,
    mixed: value == null ? true : null,
    label: label,
    hint: subtitle,
    focusable: enabled,
    onTap: enabled ? toggle : null,
    child: buildAppleRow(
      context,
      label: label,
      subtitle: subtitle,
      onTap: enabled ? toggle : null,
      control: ExcludeFocus(
        child: IgnorePointer(
          child: CupertinoCheckbox(
            value: value,
            tristate: value == null,
            // Never called: the row owns activation.
            onChanged: enabled ? (bool? _) {} : null,
            activeColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    ),
  );
}
