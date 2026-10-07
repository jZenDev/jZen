import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';

import 'focus_ring.dart';
import 'zen_progress_indicator.dart';

/// How prominent a [ZenButton] is.
enum ZenButtonVariant {
  /// Filled: the one action a screen most wants taken.
  primary,

  /// Outlined: an alternative to the primary action.
  secondary,

  /// Text only: the least prominent action, such as Cancel.
  text,
}

/// The smallest a [ZenButton] gets: 48 logical pixels tall, a comfortable pointer and touch
/// target (WCAG 2.5.8 asks for 24).
const double zenButtonMinHeight = 48;

const double _radius = 8;

const Map<ShortcutActivator, Intent> _enterActivates = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
};

/// A button that renders Cupertino on Apple platforms and Material elsewhere.
///
/// It replaces the `ElevatedButton` / `OutlinedButton` / `TextButton` an app would otherwise
/// pick per form. The framework owns the shape (variant, shared focus ring, one accessible
/// name); the app supplies the [label] and [onPressed].
///
/// * **Focus** is drawn as a [FocusRing] around the whole button — Material's own focus
///   overlay is about 1.2:1 against the surface, well short of the 3:1 WCAG 1.4.11 asks.
/// * **Name** is always [label]. While [isLoading] the button keeps the label beside a spinner
///   rather than replacing it, so a screen reader still hears what the button is.
/// * **Colour** comes from the theme's `ColorScheme` (`primary` on `onPrimary`), whose pairs
///   Material 3 keeps at AA, in light and dark. The Cupertino branch sets them explicitly
///   instead of taking iOS system blue, whose white-on-blue is 4.0:1.
///
/// A null [onPressed], or [isLoading], disables the button.
class ZenButton extends StatelessWidget {
  /// Creates a button labelled [label].
  const ZenButton({
    required this.label,
    required this.onPressed,
    this.variant = ZenButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    super.key,
  });

  /// The button's text, and its accessible name.
  final String label;

  /// Called on activation; null disables the button.
  final VoidCallback? onPressed;

  /// How prominent the button is.
  final ZenButtonVariant variant;

  /// An icon shown before the label; decorative, never the button's name.
  final IconData? icon;

  /// Shows a spinner beside the label and disables the button, for an action in flight.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? action = isLoading ? null : onPressed;
    return FocusRing.wrapping(
      child: zenIsApplePlatform
          ? buildCupertinoButton(context, label, action, variant, icon, isLoading)
          : buildMaterialButton(context, label, action, variant, icon, isLoading),
    );
  }
}

/// The label row every branch shares: optional spinner or icon, then the label, which wraps
/// rather than overflows when text is scaled to 200%.
Widget _content(String label, IconData? icon, bool isLoading) {
  return Builder(
    builder: (BuildContext context) {
      final Color? color = IconTheme.of(context).color;
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (isLoading) ...<Widget>[
            // The button's name is the label beside it; the spinner is decorative.
            ZenProgressIndicator(size: 20, color: color),
            const SizedBox(width: 8),
          ] else if (icon != null) ...<Widget>[
            ExcludeSemantics(child: Icon(icon, size: 20)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    },
  );
}

/// The Material button for [variant]. Exposed to the package's tests, which cannot reach the
/// branch the host platform did not compile.
Widget buildMaterialButton(
  BuildContext context,
  String label,
  VoidCallback? onPressed,
  ZenButtonVariant variant,
  IconData? icon,
  bool isLoading,
) {
  final Widget child = _content(label, icon, isLoading);
  const Size minimumSize = Size(64, zenButtonMinHeight);
  final OutlinedBorder shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));
  switch (variant) {
    case ZenButtonVariant.primary:
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(minimumSize: minimumSize, shape: shape),
        child: child,
      );
    case ZenButtonVariant.secondary:
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(minimumSize: minimumSize, shape: shape),
        child: child,
      );
    case ZenButtonVariant.text:
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(minimumSize: minimumSize, shape: shape),
        child: child,
      );
  }
}

/// The Cupertino button for [variant]; see [buildMaterialButton].
Widget buildCupertinoButton(
  BuildContext context,
  String label,
  VoidCallback? onPressed,
  ZenButtonVariant variant,
  IconData? icon,
  bool isLoading,
) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final bool enabled = onPressed != null;
  final Color muted = scheme.onSurface.withValues(alpha: 0.38);
  const Size minimumSize = Size(64, zenButtonMinHeight);
  final BorderRadius radius = BorderRadius.circular(_radius);

  // Colours are set here, not inherited: CupertinoButton draws its own label colour, and the
  // spinner and icon read the ambient IconTheme.
  Widget content(Color foreground) => IconTheme(
    data: IconThemeData(color: foreground),
    child: DefaultTextStyle.merge(
      style: TextStyle(color: foreground),
      child: _content(label, icon, isLoading),
    ),
  );

  // CupertinoButton says nothing about being enabled, and a disabled one still offers a tap
  // action, so a screen reader would announce it as a working button. State it: enabled is
  // merged into the button's own node, and a disabled button is replaced by a node that is a
  // disabled button with the label and no action.
  //
  // Enter is mapped to activation too: a web build maps only Space on a CupertinoButton, while a
  // native <button> answers both, and a keyboard user expects both (WCAG 2.1.1).
  Widget accessible(Widget button) => enabled
      ? Shortcuts(
          shortcuts: _enterActivates,
          child: Semantics(enabled: true, child: button),
        )
      : Semantics(
          button: true,
          enabled: false,
          label: label,
          excludeSemantics: true,
          child: button,
        );

  switch (variant) {
    case ZenButtonVariant.primary:
      return accessible(
        CupertinoButton(
          onPressed: onPressed,
          color: scheme.primary,
          disabledColor: scheme.onSurface.withValues(alpha: 0.12),
          foregroundColor: enabled ? scheme.onPrimary : muted,
          minimumSize: minimumSize,
          borderRadius: radius,
          child: content(enabled ? scheme.onPrimary : muted),
        ),
      );
    case ZenButtonVariant.secondary:
      final Color color = enabled ? scheme.primary : muted;
      return accessible(
        CupertinoButton(
          onPressed: onPressed,
          foregroundColor: color,
          minimumSize: minimumSize,
          padding: EdgeInsets.zero,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: enabled ? scheme.outline : muted),
              borderRadius: radius,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: zenButtonMinHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(widthFactor: 1, child: content(color)),
              ),
            ),
          ),
        ),
      );
    case ZenButtonVariant.text:
      final Color color = enabled ? scheme.primary : muted;
      return accessible(
        CupertinoButton(
          onPressed: onPressed,
          foregroundColor: color,
          minimumSize: minimumSize,
          child: content(color),
        ),
      );
  }
}
