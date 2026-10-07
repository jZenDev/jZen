import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';

import 'focus_ring.dart';

/// The size of a [ZenIconButton]'s target: 48 logical pixels square, a comfortable pointer and
/// touch target (WCAG 2.5.8 asks for 24).
const double zenIconButtonSize = 48;

const double _iconSize = 24;

/// The largest count a badge spells out; above it the badge says "99+", which fits its pill.
const int _badgeMax = 99;

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
/// * **Badge** is an optional count ([badge]), such as unread notifications, drawn over the icon's
///   corner. It is read with the name ("Reminders, 3"), once: the drawn digits are not a second
///   node. A null or zero [badge] draws nothing.
///
/// A null [onPressed] disables the button.
class ZenIconButton extends StatelessWidget {
  /// Creates an icon button showing [icon], named [label].
  const ZenIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badge,
    super.key,
  }) : assert(badge == null || badge >= 0, 'a badge counts things, so it is not negative');

  /// The glyph shown; decorative, never the button's name.
  final IconData icon;

  /// The button's accessible name, and its tooltip on Material.
  final String label;

  /// Called on activation; null disables the button.
  final VoidCallback? onPressed;

  /// A count shown on the icon, such as unread items; null or 0 shows none, and above 99 it reads
  /// "99+".
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return FocusRing.wrapping(
      child: zenIsApplePlatform
          ? buildCupertinoIconButton(context, icon, label, onPressed, badge: badge)
          : buildMaterialIconButton(context, icon, label, onPressed, badge: badge),
    );
  }
}

/// The badge's text for [count], or null when nothing is to be drawn.
String? _badgeText(int? count) {
  if (count == null || count <= 0) return null;
  return count > _badgeMax ? '$_badgeMax+' : '$count';
}

/// The button's accessible name: [label], then the badge's count when one shows.
String _nameWith(String label, String? badgeText) =>
    badgeText == null ? label : '$label, $badgeText';

/// [glyph] with a badge over its corner when [badgeText] is set. The digits are excluded from
/// semantics: the count is part of the button's name instead of a node beside it.
Widget _badged(Widget glyph, String? badgeText) {
  if (badgeText == null) return glyph;
  return Badge(
    label: ExcludeSemantics(child: Text(badgeText)),
    child: glyph,
  );
}

/// The Material icon button. Exposed to the package's tests, which cannot reach the branch the
/// host platform did not compile.
Widget buildMaterialIconButton(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback? onPressed, {
  int? badge,
}) {
  final String? badgeText = _badgeText(badge);
  // The name is the icon's semantic label, merged into the button, and the tooltip is excluded
  // from semantics: IconButton's own `tooltip` is announced as a tooltip, not as the button's
  // name, and naming it twice would be read twice.
  return Tooltip(
    message: label,
    excludeFromSemantics: true,
    child: IconButton(
      icon: _badged(
        Icon(icon, size: _iconSize, semanticLabel: _nameWith(label, badgeText)),
        badgeText,
      ),
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
  VoidCallback? onPressed, {
  int? badge,
}) {
  final String? badgeText = _badgeText(badge);
  final String name = _nameWith(label, badgeText);
  final bool enabled = onPressed != null;
  final Color color = enabled
      ? (IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface)
      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);

  final Widget button = CupertinoButton(
    onPressed: onPressed,
    foregroundColor: color,
    minimumSize: const Size.square(zenIconButtonSize),
    padding: EdgeInsets.zero,
    child: _badged(Icon(icon, size: _iconSize, color: color), badgeText),
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
          child: Semantics(label: name, enabled: true, child: button),
        )
      : Semantics(button: true, enabled: false, label: name, excludeSemantics: true, child: button);
}
