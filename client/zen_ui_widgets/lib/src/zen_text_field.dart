import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';

import 'zen_cupertino_text_form_field.dart';

/// A labelled text input that renders Cupertino on Apple platforms and Material elsewhere.
///
/// It is a form field, so `Form.validate()` sees it. The label is the accessible name of the
/// input itself and an error — from [validator] or [errorText] — is read with it rather than as
/// a separate node. The application supplies the label, the text and the rules; the framework
/// owns how the field looks per platform and where focus shows.
///
/// There is no trailing-widget slot: the field and its error are one merged accessible node, and
/// a control inside it would be announced as part of the field instead of on its own.
///
/// For a decimal number use `ZenAmountField`, which builds on this one.
class ZenTextField extends StatelessWidget {
  /// Creates a text field labelled [label].
  const ZenTextField({
    required this.label,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.errorText,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.autofillHints,
    this.textInputAction,
    this.enabled = true,
    super.key,
  });

  /// The field's name.
  final String label;

  /// Holds the text; the field creates its own if null.
  final TextEditingController? controller;

  /// Called on every edit with the new text.
  final ValueChanged<String>? onChanged;

  /// Called with the text when the keyboard's action key is pressed.
  final ValueChanged<String>? onSubmitted;

  /// Returns why the text is not acceptable, or null; run by `Form.validate()`.
  final FormFieldValidator<String>? validator;

  /// When [validator] runs without a `Form.validate()`.
  final AutovalidateMode autovalidateMode;

  /// An error the app decides on (a taken name, a server rejection), shown instead of
  /// [validator]'s.
  final String? errorText;

  /// Shown, dimmed, while the field is empty.
  final String? hint;

  /// Whether the text is hidden, for a password.
  final bool obscureText;

  /// The keyboard to show.
  final TextInputType? keyboardType;

  /// Shapes what is typed.
  final List<TextInputFormatter>? inputFormatters;

  /// What a password manager may fill in.
  final Iterable<String>? autofillHints;

  /// The keyboard's action key.
  final TextInputAction? textInputAction;

  /// Whether the field takes input.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return zenIsApplePlatform
        ? buildCupertinoTextField(context, this)
        : buildMaterialTextField(context, this);
  }
}

/// The Material field. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialTextField(BuildContext context, ZenTextField field) {
  // Merged so the error text is read with the field: left beside it, the error sat on a node a
  // screen reader never lands on, and the focused input was named by its label alone.
  return MergeSemantics(
    child: TextFormField(
      controller: field.controller,
      enabled: field.enabled,
      autovalidateMode: field.autovalidateMode,
      forceErrorText: field.errorText,
      obscureText: field.obscureText,
      keyboardType: field.keyboardType,
      inputFormatters: field.inputFormatters,
      autofillHints: field.autofillHints,
      textInputAction: field.textInputAction,
      onChanged: field.onChanged,
      onFieldSubmitted: field.onSubmitted,
      validator: field.validator,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.hint,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

/// The Cupertino field; see [buildMaterialTextField].
Widget buildCupertinoTextField(BuildContext context, ZenTextField field) {
  return ZenCupertinoTextFormField(
    label: field.label,
    controller: field.controller,
    onChanged: field.onChanged,
    onSubmitted: field.onSubmitted,
    validator: field.validator,
    autovalidateMode: field.autovalidateMode,
    forceErrorText: field.errorText,
    hint: field.hint,
    obscureText: field.obscureText,
    keyboardType: field.keyboardType,
    inputFormatters: field.inputFormatters,
    autofillHints: field.autofillHints,
    textInputAction: field.textInputAction,
    enabled: field.enabled,
  );
}
