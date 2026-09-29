import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import 'focus_ring.dart';
import 'picker_field.dart';
import 'wheel_popup.dart';

/// A labelled single choice from a list — currency, account, category, type.
///
/// Material dropdown everywhere except iOS, where the field opens a wheel picker: a wheel is a
/// touch idiom, and macOS, like desktop and web, keeps the keyboard-operable dropdown. The app
/// supplies the [items] and how to name them with [itemLabel]; the framework owns the field,
/// its focus ring and its single accessible name ("Currency, EUR, button").
class ZenSelect<T> extends StatelessWidget {
  /// Creates a select labelled [label] over [items].
  const ZenSelect({
    required this.label,
    required this.items,
    required this.itemLabel,
    required this.value,
    required this.onChanged,
    this.hint,
    this.errorText,
    super.key,
  });

  /// The field's name.
  final String label;

  /// The choices, in display order.
  final List<T> items;

  /// The text shown for an item.
  final String Function(T item) itemLabel;

  /// The chosen item, or null when nothing is chosen; must be one of [items].
  final T? value;

  /// Called with the item the user chose; null disables the field.
  final ValueChanged<T>? onChanged;

  /// Shown, dimmed, while [value] is null.
  final String? hint;

  /// Why the current choice is not acceptable; shown under the field and read with it.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return zenIsIOS
        ? buildCupertinoSelect<T>(context, this)
        : buildMaterialSelect<T>(context, this);
  }
}

/// The Material dropdown. Exposed to the package's tests, which cannot reach the branch the
/// host platform did not compile.
Widget buildMaterialSelect<T>(BuildContext context, ZenSelect<T> select) {
  // A DropdownButton inside an InputDecorator, which is what DropdownButtonFormField builds,
  // but controlled: the form-field variant only reads its value once, and rebuilding it with a
  // new key to work around that would drop keyboard focus on every choice.
  return FocusRing.wrapping(
    // One node: the decorator's label text and the dropdown's button merge, so the label is on
    // the node that activates rather than on a sibling nobody lands on.
    child: MergeSemantics(
      child: InputDecorator(
        isEmpty: select.value == null,
        decoration: InputDecoration(
          labelText: select.label,
          hintText: select.hint,
          errorText: select.errorText,
          enabled: select.onChanged != null,
          border: const OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            isDense: true,
            value: select.value,
            onChanged: select.onChanged == null ? null : (T? item) => select.onChanged!(item as T),
            items: <DropdownMenuItem<T>>[
              for (final T item in select.items)
                DropdownMenuItem<T>(value: item, child: Text(select.itemLabel(item))),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The iOS wheel select; see [buildMaterialSelect].
Widget buildCupertinoSelect<T>(BuildContext context, ZenSelect<T> select) {
  final T? value = select.value;
  return ZenPickerField(
    label: select.label,
    valueText: value == null ? null : select.itemLabel(value),
    placeholder: select.hint,
    errorText: select.errorText,
    onTap: select.onChanged == null ? null : () => _pickItem<T>(context, select),
  );
}

Future<void> _pickItem<T>(BuildContext context, ZenSelect<T> select) async {
  final int start = select.value == null ? 0 : select.items.indexOf(select.value as T);
  int index = start < 0 ? 0 : start;
  final T? picked = await showWheelPopup<T>(
    context,
    wheel: CupertinoPicker(
      itemExtent: 40,
      scrollController: FixedExtentScrollController(initialItem: index),
      onSelectedItemChanged: (int i) => index = i,
      children: <Widget>[
        for (final T item in select.items) Center(child: Text(select.itemLabel(item))),
      ],
    ),
    selection: () => select.items[index],
  );
  if (picked != null) select.onChanged?.call(picked);
}
