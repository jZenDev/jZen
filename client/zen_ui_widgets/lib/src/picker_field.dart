import 'package:flutter/material.dart';

import 'focus_ring.dart';

/// A read-only outlined field that opens a picker when activated — the shape a date field and
/// an iOS wheel select share.
///
/// It is **one control announced once**: the decorator's label, the value and the error text
/// merge into a single button node, so a screen reader says "Due date, 12 Jan 2026, button"
/// and the node it lands on is the one that activates. A [FocusRing] marks keyboard focus.
class ZenPickerField extends StatelessWidget {
  /// Creates a field labelled [label] showing [valueText], or [placeholder] when it is null.
  const ZenPickerField({
    required this.label,
    required this.valueText,
    required this.onTap,
    this.placeholder,
    this.errorText,
    this.icon = Icons.arrow_drop_down,
    super.key,
  });

  /// The field's name.
  final String label;

  /// The chosen value as text, or null when nothing is chosen.
  final String? valueText;

  /// Shown, dimmed, while [valueText] is null.
  final String? placeholder;

  /// Opens the picker; null disables the field.
  final VoidCallback? onTap;

  /// Why the current value is not acceptable; shown under the field and read with it.
  final String? errorText;

  /// The trailing glyph, decorative.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return FocusRing.wrapping(
      child: MergeSemantics(
        child: Semantics(
          button: true,
          enabled: onTap != null,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onTap,
            child: InputDecorator(
              isEmpty: valueText == null,
              decoration: InputDecoration(
                labelText: label,
                hintText: placeholder,
                errorText: errorText,
                enabled: onTap != null,
                border: const OutlineInputBorder(),
                suffixIcon: ExcludeSemantics(child: Icon(icon)),
              ),
              child: valueText == null ? null : Text(valueText!),
            ),
          ),
        ),
      ),
    );
  }
}
