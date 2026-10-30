import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import '../focus_ring.dart';
import 'zen_cupertino_radio_row.dart';

/// One choice in a [ZenRadioGroup].
class ZenRadioOption<T extends Object> {
  /// Creates a choice identified by [value] and shown as [label].
  const ZenRadioOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.enabled = true,
  });

  /// What the app receives when this option is chosen. Unique within its group.
  final T value;

  /// The option's text, and its accessible name.
  final String label;

  /// Optional second line explaining the option; read after the label.
  final String? subtitle;

  /// Whether the option can be chosen. A disabled option stays visible, is announced as
  /// disabled, and is skipped by the keyboard.
  final bool enabled;
}

/// A labelled group of radio options for **one choice from a longer list** — more than the two
/// to four a `ZenSegmentedControl` fits, and without the pop-up of a `ZenSelect`. Cupertino
/// radios on Apple platforms, Material elsewhere.
///
/// The app owns [value]. A null [value] is an explicit "nothing chosen yet": no option is
/// selected and [onChanged] is not called until the user picks one. A radio group never reports
/// null — once a choice is made it can be changed but not cleared; offer a "None" option when
/// that is a real answer. A [value] that matches no enabled option is shown as is and cannot be
/// reached by the keyboard. A null [onChanged] disables the whole group.
///
/// The group is announced as a radio group named [label]; each option as one control —
/// "Monthly, radio button, selected, 2 of 3". Tab enters the group on the selected option (the
/// first when nothing is selected) and leaves it; the arrow keys move the choice, skipping
/// disabled options and wrapping at the ends; a [FocusRing] marks the focused option.
class ZenRadioGroup<T extends Object> extends StatelessWidget {
  /// Creates a group named [label] offering [options].
  const ZenRadioGroup({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// What the group chooses; also its accessible name.
  final String label;

  /// The choices, in display order. At least two, with distinct values.
  final List<ZenRadioOption<T>> options;

  /// The value of the chosen option, or null when none is chosen.
  final T? value;

  /// Called with the value of the option the user chose; null disables the group.
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    assert(options.length >= 2, 'a radio group offers at least two options');
    assert(
      options.map((ZenRadioOption<T> option) => option.value).toSet().length == options.length,
      'radio option values must be unique',
    );
    return zenIsApplePlatform
        ? buildCupertinoRadioGroup<T>(context, label, options, value, onChanged)
        : buildMaterialRadioGroup<T>(context, label, options, value, onChanged);
  }
}

/// The Material group. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialRadioGroup<T extends Object>(
  BuildContext context,
  String label,
  List<ZenRadioOption<T>> options,
  T? value,
  ValueChanged<T>? onChanged,
) {
  return _group<T>(context, label, value, onChanged, <Widget>[
    for (final ZenRadioOption<T> option in options)
      FocusRing.wrapping(
        child: RadioListTile<T>(
          value: option.value,
          enabled: onChanged != null && option.enabled,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(option.label),
          subtitle: option.subtitle == null ? null : Text(option.subtitle!),
        ),
      ),
  ]);
}

/// The Cupertino group; see [buildMaterialRadioGroup].
Widget buildCupertinoRadioGroup<T extends Object>(
  BuildContext context,
  String label,
  List<ZenRadioOption<T>> options,
  T? value,
  ValueChanged<T>? onChanged,
) {
  return _group<T>(context, label, value, onChanged, <Widget>[
    for (final ZenRadioOption<T> option in options)
      FocusRing.wrapping(
        child: ZenCupertinoRadioRow<T>(option: option, groupEnabled: onChanged != null),
      ),
  ]);
}

/// The group's shell: the visible [label], the options, and the [RadioGroup] that owns the value
/// and the keyboard (Tab into the selected option, arrows to move, Space to choose).
Widget _group<T extends Object>(
  BuildContext context,
  String label,
  T? value,
  ValueChanged<T>? onChanged,
  List<Widget> rows,
) {
  final ThemeData theme = Theme.of(context);
  return Semantics(
    container: true,
    explicitChildNodes: true,
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The group is named on its own node; the visible text is not a second reader stop.
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(label, style: theme.textTheme.titleSmall),
          ),
        ),
        RadioGroup<T>(
          groupValue: value,
          onChanged: (T? chosen) {
            if (chosen != null) onChanged?.call(chosen);
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        ),
      ],
    ),
  );
}
