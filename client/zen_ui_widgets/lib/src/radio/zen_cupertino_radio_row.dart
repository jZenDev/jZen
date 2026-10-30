import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../apple_row.dart';
import 'zen_radio_group.dart';

/// One Cupertino option of a `ZenRadioGroup`: the row is the tap target, the [CupertinoRadio]
/// inside is the single focus stop and the node that carries the radio semantics, and the row's
/// text is merged into it.
///
/// Internal to the package: not exported.
class ZenCupertinoRadioRow<T extends Object> extends StatelessWidget {
  /// Creates the row for [option].
  const ZenCupertinoRadioRow({required this.option, required this.groupEnabled, super.key});

  /// The choice this row shows.
  final ZenRadioOption<T> option;

  /// False when the whole group is disabled.
  final bool groupEnabled;

  @override
  Widget build(BuildContext context) {
    final RadioGroupRegistry<T>? group = RadioGroup.maybeOf<T>(context);
    final bool enabled = groupEnabled && option.enabled;
    return MergeSemantics(
      child: buildAppleRow(
        context,
        label: option.label,
        subtitle: option.subtitle,
        // Not the radio's own tap target: the whole row is one, so a label tap chooses too.
        onTap: enabled ? () => group?.onChanged(option.value) : null,
        focusable: false,
        control: IgnorePointer(
          child: CupertinoRadio<T>(
            value: option.value,
            enabled: enabled,
            activeColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
