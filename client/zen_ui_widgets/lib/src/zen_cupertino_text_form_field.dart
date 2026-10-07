import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'focus_ring.dart';

/// The Cupertino half of `ZenTextField`: a labelled [CupertinoTextField] that is also a
/// [FormField], so `Form.validate()` sees it as it would a Material `TextFormField`.
///
/// `CupertinoTextFormFieldRow` is not used because it is a list-row idiom: it has no forced
/// error, no trailing widget, and its error text is a separate node a screen reader never lands
/// on. This lays out a label above a bordered field with the error beneath, and merges all three
/// into one accessible node so the label and the error are read with the field.
class ZenCupertinoTextFormField extends FormField<String> {
  /// Creates a field labelled [label].
  ZenCupertinoTextFormField({
    required this.label,
    this.controller,
    this.onChanged,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.autofillHints,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onSubmitted,
    super.validator,
    super.autovalidateMode,
    super.forceErrorText,
    super.enabled,
    super.key,
  }) : super(
         initialValue: controller?.text ?? '',
         builder: (FormFieldState<String> field) {
           final _State state = field as _State;
           final ThemeData theme = Theme.of(field.context);
           final ColorScheme scheme = theme.colorScheme;
           final String? error = field.errorText;
           final bool invalid = error != null;
           final Color border = invalid ? scheme.error : scheme.outline;

           return MergeSemantics(
             child: Semantics(
               label: label,
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: <Widget>[
                   // Named by the merged node's label; read twice if left in the tree.
                   ExcludeSemantics(
                     child: Text(
                       label,
                       style: theme.textTheme.bodyMedium?.copyWith(
                         fontWeight: FontWeight.w600,
                         color: scheme.onSurface,
                       ),
                     ),
                   ),
                   const SizedBox(height: 6),
                   FocusRing.wrapping(
                     child: CupertinoTextField(
                       controller: state._effectiveController,
                       enabled: enabled,
                       obscureText: obscureText,
                       keyboardType: keyboardType,
                       inputFormatters: inputFormatters,
                       autofillHints: autofillHints,
                       textInputAction: textInputAction,
                       textCapitalization: textCapitalization,
                       maxLines: maxLines,
                       minLines: minLines,
                       maxLength: maxLength,
                       placeholder: hint,
                       // Set rather than inherited: CupertinoTextField's defaults are the iOS
                       // system greys, a hairline border and a placeholder well under 4.5:1.
                       style: TextStyle(color: scheme.onSurface),
                       placeholderStyle: TextStyle(color: scheme.onSurfaceVariant),
                       cursorColor: scheme.primary,
                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                       decoration: BoxDecoration(
                         color: scheme.surface,
                         border: Border.all(color: border, width: invalid ? 2 : 1),
                         borderRadius: BorderRadius.circular(8),
                       ),
                       onChanged: (String text) {
                         field.didChange(text);
                         onChanged?.call(text);
                       },
                       onSubmitted: onSubmitted,
                     ),
                   ),
                   if (invalid || maxLength != null) ...<Widget>[
                     const SizedBox(height: 4),
                     Row(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: <Widget>[
                         Expanded(
                           child: invalid
                               ? Text(
                                   error,
                                   style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                                 )
                               : const SizedBox.shrink(),
                         ),
                         if (maxLength != null)
                           // Material's counter reads "n / max"; the slash alone is not a word.
                           Text(
                             '${(field.value ?? '').characters.length}/$maxLength',
                             semanticsLabel:
                                 '${(field.value ?? '').characters.length} / $maxLength',
                             style: theme.textTheme.bodySmall?.copyWith(
                               color: scheme.onSurfaceVariant,
                             ),
                           ),
                       ],
                     ),
                   ],
                 ],
               ),
             ),
           );
         },
       );

  /// The field's name.
  final String label;

  /// Holds the text; the field creates its own if null.
  final TextEditingController? controller;

  /// Called on every edit with the new text.
  final ValueChanged<String>? onChanged;

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

  /// How the keyboard capitalizes what is typed.
  final TextCapitalization textCapitalization;

  /// The most lines the field grows to before it scrolls; null is no limit.
  final int? maxLines;

  /// The fewest lines the field shows.
  final int? minLines;

  /// The most characters accepted; when set, a counter is shown under the field.
  final int? maxLength;

  /// Called with the text when the keyboard's action key is pressed.
  final ValueChanged<String>? onSubmitted;

  @override
  FormFieldState<String> createState() => _State();
}

class _State extends FormFieldState<String> {
  TextEditingController? _own;

  TextEditingController get _effectiveController => _field.controller ?? _own!;

  ZenCupertinoTextFormField get _field => super.widget as ZenCupertinoTextFormField;

  @override
  void initState() {
    super.initState();
    if (_field.controller == null) {
      _own = TextEditingController(text: widget.initialValue);
    } else {
      _field.controller!.addListener(_handleControllerChanged);
    }
  }

  @override
  void didUpdateWidget(ZenCupertinoTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_field.controller == oldWidget.controller) return;
    oldWidget.controller?.removeListener(_handleControllerChanged);
    _field.controller?.addListener(_handleControllerChanged);
    if (oldWidget.controller != null && _field.controller == null) {
      _own = TextEditingController.fromValue(oldWidget.controller!.value);
    }
    if (_field.controller != null) {
      setValue(_field.controller!.text);
      if (oldWidget.controller == null) {
        _own!.dispose();
        _own = null;
      }
    }
  }

  @override
  void dispose() {
    _field.controller?.removeListener(_handleControllerChanged);
    _own?.dispose();
    super.dispose();
  }

  @override
  void didChange(String? value) {
    super.didChange(value);
    if (value != null && _effectiveController.text != value) {
      _effectiveController.value = TextEditingValue(text: value);
    }
  }

  @override
  void reset() {
    // The controller first, so _handleControllerChanged sees nothing left to sync.
    _effectiveController.value = TextEditingValue(text: widget.initialValue ?? '');
    super.reset();
    _field.onChanged?.call(_effectiveController.text);
  }

  void _handleControllerChanged() {
    // Edits that began in this class have already set the field's value.
    if (_effectiveController.text != value) didChange(_effectiveController.text);
  }
}
