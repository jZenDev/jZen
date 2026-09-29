import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import 'focus_ring.dart';

/// A labelled on/off row for a boolean setting: the label on the left, a switch on the right,
/// the whole row one tap target. Cupertino switch on Apple platforms, Material elsewhere.
///
/// The row is **one control announced once** — "Archived, switch, on" — with the label, role
/// and state on the node that takes focus and activates with Space or Enter. A [FocusRing]
/// surrounds the row while it holds keyboard focus.
class ZenSwitchRow extends StatelessWidget {
  /// Creates a row labelled [label].
  const ZenSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  /// What the switch controls; also its accessible name.
  final String label;

  /// Whether the setting is on.
  final bool value;

  /// Called with the new value; null disables the row.
  final ValueChanged<bool>? onChanged;

  /// Optional second line explaining the setting; read after the label.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return FocusRing.wrapping(
      child: zenIsApplePlatform
          ? buildCupertinoSwitchRow(context, label, subtitle, value, onChanged)
          : buildMaterialSwitchRow(context, label, subtitle, value, onChanged),
    );
  }
}

/// The Material row. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialSwitchRow(
  BuildContext context,
  String label,
  String? subtitle,
  bool value,
  ValueChanged<bool>? onChanged,
) {
  return SwitchListTile(
    value: value,
    onChanged: onChanged,
    title: Text(label),
    subtitle: subtitle == null ? null : Text(subtitle),
  );
}

/// The Cupertino row; see [buildMaterialSwitchRow].
///
/// A [CupertinoSwitch] alone has no label and only the switch is tappable, so the row is the
/// control: an [InkWell] that toggles, with the switch drawn inside it but taken out of focus
/// and hit testing so there is one tab stop and one node, not two.
Widget buildCupertinoSwitchRow(
  BuildContext context,
  String label,
  String? subtitle,
  bool value,
  ValueChanged<bool>? onChanged,
) {
  final bool enabled = onChanged != null;
  final ThemeData theme = Theme.of(context);
  final TextStyle? subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );

  return Semantics(
    container: true,
    excludeSemantics: true,
    enabled: enabled,
    toggled: value,
    label: label,
    hint: subtitle,
    focusable: enabled,
    onTap: enabled ? () => onChanged(!value) : null,
    child: InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: theme.textTheme.bodyLarge),
                    if (subtitle != null) Text(subtitle, style: subtitleStyle),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ExcludeFocus(
                child: IgnorePointer(
                  child: CupertinoSwitch(
                    value: value,
                    // Never called: the row above owns activation.
                    onChanged: enabled ? (bool _) {} : null,
                    activeTrackColor: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
