import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import 'focus_ring.dart';

/// One choice in a [ZenSegmentedControl].
class ZenSegment<T extends Object> {
  /// Creates a choice identified by [value] and shown as [label].
  const ZenSegment({required this.value, required this.label});

  /// What the app receives when this segment is chosen.
  final T value;

  /// The segment's text, and its accessible name.
  final String label;
}

/// A row of two to four mutually exclusive choices — a transaction type, a view mode — where
/// exactly one is always selected. Sliding Cupertino control on Apple platforms, Material
/// `SegmentedButton` elsewhere.
///
/// The keyboard follows each idiom's own pattern, and both show a [FocusRing]. Material's
/// segments are separate tab stops, each ringed. Cupertino's control is a radio group: Tab lands
/// on the chosen segment, the arrow keys move the choice, and the whole control is ringed
/// because focus and choice are the same thing there. Selection is announced as state, not as a
/// second label.
class ZenSegmentedControl<T extends Object> extends StatelessWidget {
  /// Creates a control offering [segments], with [selected] chosen.
  const ZenSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// The choices, in display order.
  final List<ZenSegment<T>> segments;

  /// The value of the chosen segment.
  final T selected;

  /// Called with the value of the segment the user chose.
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return zenIsApplePlatform
        ? FocusRing.wrapping(
            child: buildCupertinoSegmentedControl<T>(context, segments, selected, onChanged),
          )
        : buildMaterialSegmentedControl<T>(context, segments, selected, onChanged);
  }
}

/// The Material control. Exposed to the package's tests, which cannot reach the branch the
/// host platform did not compile.
Widget buildMaterialSegmentedControl<T extends Object>(
  BuildContext context,
  List<ZenSegment<T>> segments,
  T selected,
  ValueChanged<T>? onChanged,
) {
  return SegmentedButton<T>(
    showSelectedIcon: false,
    segments: <ButtonSegment<T>>[
      for (final ZenSegment<T> segment in segments)
        ButtonSegment<T>(
          value: segment.value,
          // Inside the segment's own focusable, where a FocusRing reads its state.
          label: FocusRing(child: Text(segment.label)),
        ),
    ],
    selected: <T>{selected},
    onSelectionChanged: onChanged == null ? null : (Set<T> chosen) => onChanged(chosen.first),
  );
}

/// The Cupertino control; see [buildMaterialSegmentedControl].
Widget buildCupertinoSegmentedControl<T extends Object>(
  BuildContext context,
  List<ZenSegment<T>> segments,
  T selected,
  ValueChanged<T>? onChanged,
) {
  return CupertinoSlidingSegmentedControl<T>(
    groupValue: selected,
    // Not a `null` value: the control reports one only when it is disabled.
    onValueChanged: (T? value) {
      if (value != null && onChanged != null) onChanged(value);
    },
    proportionalWidth: false,
    children: <T, Widget>{
      for (final ZenSegment<T> segment in segments)
        segment.value: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(segment.label, style: TextStyle(color: _label(context))),
        ),
    },
  );
}

Color _label(BuildContext context) => Theme.of(context).colorScheme.onSurface;
