import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';

import '../button/zen_icon_button.dart';
import '../l10n/generated/zen_widgets_localizations.dart';
import 'zen_cupertino_text_form_field.dart';

/// A labelled text input that renders Cupertino on Apple platforms and Material elsewhere.
///
/// It is a form field, so `Form.validate()` sees it. The label is the accessible name of the
/// input itself and an error — from [validator] or [errorText] — is read with it rather than as
/// a separate node. The application supplies the label, the text and the rules; the framework
/// owns how the field looks per platform and where focus shows.
///
/// There is no trailing-widget slot: the field and its error are one merged accessible node, and
/// a control inside it would be announced as part of the field instead of on its own. The one
/// control a field offers is [revealable]'s show/hide button, which sits *beside* that node, so a
/// screen reader meets it as a separate, named button and a keyboard reaches it as its own Tab
/// stop. It speaks "Show password" / "Hide password"; register `zenWidgetsLocaleDelegate`.
///
/// For a decimal number use `ZenAmountField`, which builds on this one.
class ZenTextField extends StatefulWidget {
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
    this.revealable = false,
    this.keyboardType,
    this.inputFormatters,
    this.autofillHints,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.enabled = true,
    super.key,
  }) : assert(maxLines == null || maxLines > 0, 'maxLines must be positive'),
       assert(minLines == null || minLines > 0, 'minLines must be positive'),
       assert(
         minLines == null || maxLines == null || minLines <= maxLines,
         'minLines cannot exceed maxLines',
       ),
       assert(maxLength == null || maxLength > 0, 'maxLength must be positive'),
       assert(!obscureText || maxLines == 1, 'a hidden text is a single line'),
       assert(!revealable || obscureText, 'only a hidden text can be revealed');

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

  /// Whether a button beside the field shows and hides the [obscureText]'d text, so a password
  /// typed, pasted or filled in by a password manager can be checked. Requires [obscureText];
  /// the text starts hidden. Off by default: hiding a PIN may be deliberate.
  final bool revealable;

  /// The keyboard to show.
  final TextInputType? keyboardType;

  /// Shapes what is typed.
  final List<TextInputFormatter>? inputFormatters;

  /// What a password manager may fill in.
  final Iterable<String>? autofillHints;

  /// The keyboard's action key.
  final TextInputAction? textInputAction;

  /// How the keyboard capitalizes what is typed; a hint to the keyboard, not a rule on the text.
  /// To force upper case, use an [inputFormatters] entry.
  final TextCapitalization textCapitalization;

  /// The most lines the field grows to before it scrolls; 1 (the default) is a single line, null
  /// is no limit. More than one makes it a multiline note.
  final int? maxLines;

  /// The fewest lines the field shows, so an empty note is already a box to write in; null is
  /// [maxLines]'s own start.
  final int? minLines;

  /// The most characters the field accepts. When set, the field shows a counter of how many are
  /// used, and typing past the limit is refused.
  final int? maxLength;

  /// Whether the field takes input.
  final bool enabled;

  @override
  State<ZenTextField> createState() => _ZenTextFieldState();
}

class _ZenTextFieldState extends State<ZenTextField> {
  bool _revealed = false;

  void _toggle() => setState(() => _revealed = !_revealed);

  @override
  Widget build(BuildContext context) {
    return zenIsApplePlatform
        ? buildCupertinoTextField(context, widget, revealed: _revealed, onToggleReveal: _toggle)
        : buildMaterialTextField(context, widget, revealed: _revealed, onToggleReveal: _toggle);
  }
}

/// The show/hide button of a [ZenTextField.revealable]: named for what pressing it does.
Widget _revealButton(
  BuildContext context,
  ZenTextField field,
  bool revealed,
  VoidCallback? toggle,
) {
  final ZenWidgetsLocalizations messages = ZenWidgetsLocalizations.of(context);
  return ZenIconButton(
    icon: revealed ? Icons.visibility_off : Icons.visibility,
    label: revealed ? messages.hidePassword : messages.showPassword,
    onPressed: field.enabled ? toggle : null,
  );
}

/// The Material field. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialTextField(
  BuildContext context,
  ZenTextField field, {
  bool revealed = false,
  VoidCallback? onToggleReveal,
}) {
  // Merged so the error text is read with the field: left beside it, the error sat on a node a
  // screen reader never lands on, and the focused input was named by its label alone.
  final Widget input = MergeSemantics(
    child: TextFormField(
      controller: field.controller,
      enabled: field.enabled,
      autovalidateMode: field.autovalidateMode,
      forceErrorText: field.errorText,
      obscureText: field.obscureText && !revealed,
      keyboardType: field.keyboardType,
      inputFormatters: field.inputFormatters,
      autofillHints: field.autofillHints,
      textInputAction: field.textInputAction,
      textCapitalization: field.textCapitalization,
      maxLines: field.maxLines,
      minLines: field.minLines,
      maxLength: field.maxLength,
      onChanged: field.onChanged,
      onFieldSubmitted: field.onSubmitted,
      validator: field.validator,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.hint,
        // A tall box's label starts at the top with the text, not at its middle.
        alignLabelWithHint: field.maxLines != 1,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  if (!field.revealable) return input;
  // The 48-pixel button is centred on the 56-pixel input box, not on the error text beneath it.
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(child: input),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: _revealButton(context, field, revealed, onToggleReveal),
      ),
    ],
  );
}

/// The Cupertino field; see [buildMaterialTextField].
Widget buildCupertinoTextField(
  BuildContext context,
  ZenTextField field, {
  bool revealed = false,
  VoidCallback? onToggleReveal,
}) {
  return ZenCupertinoTextFormField(
    label: field.label,
    controller: field.controller,
    onChanged: field.onChanged,
    onSubmitted: field.onSubmitted,
    validator: field.validator,
    autovalidateMode: field.autovalidateMode,
    forceErrorText: field.errorText,
    hint: field.hint,
    obscureText: field.obscureText && !revealed,
    keyboardType: field.keyboardType,
    inputFormatters: field.inputFormatters,
    autofillHints: field.autofillHints,
    textInputAction: field.textInputAction,
    textCapitalization: field.textCapitalization,
    maxLines: field.maxLines,
    minLines: field.minLines,
    maxLength: field.maxLength,
    enabled: field.enabled,
    trailing: field.revealable ? _revealButton(context, field, revealed, onToggleReveal) : null,
  );
}
