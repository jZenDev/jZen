import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';

import '../button/zen_icon_button.dart';
import '../focus_ring.dart';
import '../l10n/generated/zen_widgets_localizations.dart';

/// A labelled search input with a clear button: a rounded outlined field with a magnifier on
/// Material, a capsule on Apple platforms.
///
/// The widget owns the *input*, not the search. The text, the data being searched, the ranking and
/// when to run it all stay with the app, which reads the text from [controller] or [onChanged] and
/// decides what to show — including an empty result.
///
/// **Controller ownership.** Pass a [controller] and it is yours: the field reads and writes it
/// and never disposes it. Pass none and the field creates one for its own lifetime. Either way
/// the clear button empties the controller, calls [onChanged] with `''` and puts focus back in the
/// field so typing can go on.
///
/// **States.** An empty field shows the [hint] (or the [label]) and no clear button. Once there is
/// text a clear button named by a localized "Clear search" appears — it is a separate tab stop and
/// a separate accessible control from the field, which is what lets a keyboard or screen-reader
/// user reach it. Escape clears a non-empty field too. A disabled field ([enabled] false) keeps
/// showing its text, takes no input and offers no clear button.
///
/// The field is announced by its [label] — "Search accounts, search field" — and the label reflows
/// at large text sizes. Register `zenWidgetsLocaleDelegate` for the clear button's name.
///
/// Use `ZenTextField` for any other text: it has no clear button, because a control inside a text
/// field would be announced as part of it.
class ZenSearchField extends StatefulWidget {
  /// Creates a search field named [label].
  const ZenSearchField({
    required this.label,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.hint,
    this.enabled = true,
    this.autofocus = false,
    super.key,
  });

  /// What is being searched; the field's accessible name, such as "Search accounts".
  final String label;

  /// Holds the text. The field creates and disposes its own when null; a controller passed in
  /// stays the caller's to dispose.
  final TextEditingController? controller;

  /// Called on every edit, and with `''` when the clear button or Escape empties the field.
  final ValueChanged<String>? onChanged;

  /// Called with the text when the keyboard's search key is pressed.
  final ValueChanged<String>? onSubmitted;

  /// Shown, dimmed, while the field is empty; [label] when null.
  final String? hint;

  /// Whether the field takes input.
  final bool enabled;

  /// Whether the field takes focus when first shown.
  final bool autofocus;

  @override
  State<ZenSearchField> createState() => _ZenSearchFieldState();
}

class _ZenSearchFieldState extends State<ZenSearchField> {
  TextEditingController? _own;
  final FocusNode _focus = FocusNode(debugLabel: 'ZenSearchField');

  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final String clearLabel = ZenWidgetsLocalizations.of(context).clearSearch;
    return zenIsApplePlatform
        ? buildCupertinoSearchField(
            context,
            label: widget.label,
            hint: widget.hint,
            controller: _controller,
            focusNode: _focus,
            clearLabel: clearLabel,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            onClear: _clear,
          )
        : buildMaterialSearchField(
            context,
            label: widget.label,
            hint: widget.hint,
            controller: _controller,
            focusNode: _focus,
            clearLabel: clearLabel,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            onClear: _clear,
          );
  }
}

/// Escape empties a field that has text; with none it is left alone, so it still closes a dialog.
Widget _escapeClears(TextEditingValue value, VoidCallback onClear, Widget child) {
  return CallbackShortcuts(
    bindings: value.text.isEmpty
        ? const <ShortcutActivator, VoidCallback>{}
        : <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): onClear,
          },
    child: child,
  );
}

/// The Material field. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialSearchField(
  BuildContext context, {
  required String label,
  required TextEditingController controller,
  required FocusNode focusNode,
  required String clearLabel,
  required bool enabled,
  required VoidCallback onClear,
  String? hint,
  bool autofocus = false,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
}) {
  return ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (BuildContext context, TextEditingValue value, Widget? _) => _escapeClears(
      value,
      onClear,
      TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: const ExcludeSemantics(child: Icon(Icons.search)),
          suffixIcon: value.text.isNotEmpty && enabled
              ? ZenIconButton(icon: Icons.close, label: clearLabel, onPressed: onClear)
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
        ),
      ),
    ),
  );
}

/// The Cupertino field; see [buildMaterialSearchField].
///
/// A [CupertinoSearchTextField] clears with an icon button that has no name a screen reader can
/// read, so the capsule is assembled from a [CupertinoTextField] and the framework's own labelled
/// `ZenIconButton` instead.
Widget buildCupertinoSearchField(
  BuildContext context, {
  required String label,
  required TextEditingController controller,
  required FocusNode focusNode,
  required String clearLabel,
  required bool enabled,
  required VoidCallback onClear,
  String? hint,
  bool autofocus = false,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
}) {
  final ThemeData theme = Theme.of(context);
  final ColorScheme colors = theme.colorScheme;
  final Color muted = enabled ? colors.onSurfaceVariant : theme.disabledColor;

  return ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (BuildContext context, TextEditingValue value, Widget? _) => _escapeClears(
      value,
      onClear,
      DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          border: Border.all(color: enabled ? colors.outline : theme.disabledColor),
          borderRadius: BorderRadius.circular(22),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: ExcludeSemantics(child: Icon(CupertinoIcons.search, size: 20, color: muted)),
              ),
              Expanded(
                child: FocusRing.wrapping(
                  child: MergeSemantics(
                    child: Semantics(
                      label: label,
                      child: CupertinoTextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: enabled,
                        autofocus: autofocus,
                        textInputAction: TextInputAction.search,
                        placeholder: hint ?? label,
                        style: TextStyle(color: enabled ? colors.onSurface : theme.disabledColor),
                        placeholderStyle: TextStyle(color: muted),
                        cursorColor: colors.primary,
                        decoration: null,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                        onChanged: onChanged,
                        onSubmitted: onSubmitted,
                      ),
                    ),
                  ),
                ),
              ),
              if (value.text.isNotEmpty && enabled)
                ZenIconButton(
                  icon: CupertinoIcons.xmark_circle_fill,
                  label: clearLabel,
                  onPressed: onClear,
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    ),
  );
}
