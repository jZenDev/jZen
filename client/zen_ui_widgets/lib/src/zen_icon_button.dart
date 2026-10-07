import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';

import 'focus_ring.dart';

/// The size of a [ZenIconButton]'s target: 48 logical pixels square, a comfortable pointer and
/// touch target (WCAG 2.5.8 asks for 24).
const double zenIconButtonSize = 48;

const double _iconSize = 24;

const Map<ShortcutActivator, Intent> _enterActivates = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
};

/// An icon-only button that renders Cupertino on Apple platforms and Material elsewhere.
///
/// It replaces the `IconButton` an app would otherwise reach for in an app bar or beside a field.
/// The framework owns the shape; the app supplies the [icon], the [label] and [onPressed].
///
/// * **Name** is always [label]. An icon says nothing to a screen reader, so the label is
///   required: it is the accessible name on both idioms and also the tooltip on Material.
/// * **Focus** is drawn as a [FocusRing] around the whole button, as for `ZenButton`.
/// * **Colour** is the ambient `IconTheme`'s, so a button in an `AppBar` takes the bar's
///   foreground; outside one it falls back to the theme's `onSurface`.
///
/// A null [onPressed] disables the button.
class ZenIconButton extends StatelessWidget {
  /// Creates an icon button showing [icon], named [label].
  const ZenIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// The glyph shown; decorative, never the button's name.
  final IconData icon;

  /// The button's accessible name, and its tooltip on Material.
  final String label;

  /// Called on activation; null disables the button.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FocusRing.wrapping(
      child: zenIsApplePlatform
          ? buildCupertinoIconButton(context, icon, label, onPressed)
          : buildMaterialIconButton(context, icon, label, onPressed),
    );
  }
}

/// The Material icon button. Exposed to the package's tests, which cannot reach the branch the
/// host platform did not compile.
Widget buildMaterialIconButton(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback? onPressed,
) {
  // The name is the icon's semantic label, merged into the button, and the tooltip is excluded
  // from semantics: IconButton's own `tooltip` is announced as a tooltip, not as the button's
  // name, and naming it twice would be read twice.
  return Tooltip(
    message: label,
    excludeFromSemantics: true,
    child: IconButton(
      icon: Icon(icon, size: _iconSize, semanticLabel: label),
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(
        width: zenIconButtonSize,
        height: zenIconButtonSize,
      ),
    ),
  );
}

/// The Cupertino icon button; see [buildMaterialIconButton].
Widget buildCupertinoIconButton(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback? onPressed,
) {
  final bool enabled = onPressed != null;
  final Color color = enabled
      ? (IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface)
      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);

  final Widget button = CupertinoButton(
    onPressed: onPressed,
    foregroundColor: color,
    minimumSize: const Size.square(zenIconButtonSize),
    padding: EdgeInsets.zero,
    child: Icon(icon, size: _iconSize, color: color),
  );

  // CupertinoButton says nothing about being enabled, and a disabled one still offers a tap
  // action, so a screen reader would announce it as a working button. State it: an enabled
  // button is named and flagged enabled, and a disabled one is replaced by a node that is a
  // disabled button with the label and no action. The icon carries no name of its own.
  //
  // Enter is mapped to activation too: a web build maps only Space on a CupertinoButton, while a
  // native <button> answers both, and a keyboard user expects both (WCAG 2.1.1).
  return enabled
      ? Shortcuts(
          shortcuts: _enterActivates,
          child: Semantics(label: label, enabled: true, child: button),
        )
      : Semantics(
          button: true,
          enabled: false,
          label: label,
          excludeSemantics: true,
          child: button,
        );
}
