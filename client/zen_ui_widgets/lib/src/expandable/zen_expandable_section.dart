import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import '../adaptive_ink_well.dart';
import '../focus_ring.dart';
import 'zen_expandable_body.dart';

/// A labelled header that shows or hides the content beneath it: a Material list-tile header with
/// a chevron elsewhere, a Cupertino disclosure row with a turning chevron on Apple platforms.
///
/// **State.** The app owns it: [expanded] says whether the content shows and [onChanged] receives
/// the value the user asks for when they activate the header. A section the app never updates
/// does not move. A null [onChanged] disables the header — it stays readable, is announced as
/// disabled, takes no focus, and the content stays as [expanded] has it.
///
/// **Collapsed content.** It is not painted, cannot be focused and is not read by a screen reader,
/// so a collapsed field is not a hidden tab stop. By default the content is *discarded* once the
/// section has closed and built afresh when it opens; set [maintainState] to keep it mounted,
/// and so keep what the user typed or scrolled, while it is out of sight.
///
/// The header is one control — "Advanced options, button, expanded" — with one tab stop, activated
/// by Space or Enter and ringed by a [FocusRing] while focused. A long title wraps. The content
/// opens with a short size animation, which is skipped when the system asks for reduced motion.
class ZenExpandableSection extends StatelessWidget {
  /// Creates a section titled [title] around [child].
  const ZenExpandableSection({
    required this.title,
    required this.expanded,
    required this.onChanged,
    required this.child,
    this.subtitle,
    this.maintainState = false,
    super.key,
  });

  /// The header's text, and its accessible name.
  final String title;

  /// Optional second line under the title; read after it.
  final String? subtitle;

  /// Whether the content is shown.
  final bool expanded;

  /// Called with the value the user asks for — the opposite of [expanded]; null disables the
  /// header.
  final ValueChanged<bool>? onChanged;

  /// The content shown while expanded.
  final Widget child;

  /// Whether the content keeps its state while collapsed.
  final bool maintainState;

  @override
  Widget build(BuildContext context) {
    return zenIsApplePlatform
        ? buildCupertinoExpandableSection(
            context,
            title,
            subtitle,
            expanded,
            onChanged,
            maintainState,
            child,
          )
        : buildMaterialExpandableSection(
            context,
            title,
            subtitle,
            expanded,
            onChanged,
            maintainState,
            child,
          );
  }
}

/// The section's two parts, stacked: [header], then the collapsible [child].
Widget _section(Widget header, bool expanded, bool maintainState, Widget child) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: <Widget>[
    header,
    ZenExpandableBody(expanded: expanded, maintainState: maintainState, child: child),
  ],
);

Duration _turn(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : zenExpandableDuration;

/// The Material section. Exposed to the package's tests, which cannot reach the branch the host
/// platform did not compile.
Widget buildMaterialExpandableSection(
  BuildContext context,
  String title,
  String? subtitle,
  bool expanded,
  ValueChanged<bool>? onChanged,
  bool maintainState,
  Widget child,
) {
  final bool enabled = onChanged != null;
  return _section(
    FocusRing.wrapping(
      // Merged, so "expanded" is a state of the header's own node rather than of a node around it.
      child: MergeSemantics(
        child: Semantics(
          expanded: expanded,
          child: ListTile(
            enabled: enabled,
            onTap: enabled ? () => onChanged(!expanded) : null,
            title: Text(title),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: ExcludeSemantics(
              child: AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: _turn(context),
                child: const Icon(Icons.expand_more),
              ),
            ),
          ),
        ),
      ),
    ),
    expanded,
    maintainState,
    child,
  );
}

/// The Cupertino section; see [buildMaterialExpandableSection].
///
/// A disclosure row: an ink-free tap target, at least 48 points tall, with a chevron that turns
/// from pointing along the text to pointing down. It is drawn from a plain tap target because a
/// Material list tile would bring its ripple to Apple platforms.
Widget buildCupertinoExpandableSection(
  BuildContext context,
  String title,
  String? subtitle,
  bool expanded,
  ValueChanged<bool>? onChanged,
  bool maintainState,
  Widget child,
) {
  final bool enabled = onChanged != null;
  final ThemeData theme = Theme.of(context);
  final Color? textColor = enabled ? null : theme.disabledColor;
  // The chevron points along the text; a quarter turn makes it point down in either direction.
  final double quarter = Directionality.of(context) == TextDirection.rtl ? -0.25 : 0.25;
  void toggle() => onChanged?.call(!expanded);

  return _section(
    FocusRing.wrapping(
      child: Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        enabled: enabled,
        expanded: expanded,
        label: title,
        hint: subtitle,
        focusable: enabled,
        onTap: enabled ? toggle : null,
        child: buildCupertinoInkWell(
          onTap: enabled ? toggle : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: theme.textTheme.bodyLarge?.copyWith(color: textColor)),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: textColor ?? theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  AnimatedRotation(
                    turns: expanded ? quarter : 0,
                    duration: _turn(context),
                    child: Icon(
                      CupertinoIcons.chevron_forward,
                      size: 18,
                      color: textColor ?? theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    expanded,
    maintainState,
    child,
  );
}
