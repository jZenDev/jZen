import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_core/zen_core.dart';

import 'focus_ring.dart';

/// An adaptive list row. Supply either text or a widget for each text slot.
class ZenListRow extends StatelessWidget {
  const ZenListRow({
    this.title,
    this.titleContent,
    this.subtitle,
    this.subtitleContent,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    super.key,
  }) : assert((title == null) != (titleContent == null)),
       assert(subtitle == null || subtitleContent == null);

  final String? title;
  final Widget? titleContent;
  final String? subtitle;
  final Widget? subtitleContent;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  Widget get _titleWidget =>
      titleContent ?? Text(title!, maxLines: 2, overflow: TextOverflow.ellipsis);

  Widget? get _subtitleWidget =>
      subtitleContent ??
      (subtitle == null ? null : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis));

  @override
  Widget build(BuildContext context) => zenIsApplePlatform
      ? buildCupertinoListRow(context, this)
      : buildMaterialListRow(context, this);
}

/// Builds the Cupertino implementation for platform-independent tests.
Widget buildCupertinoListRow(BuildContext context, ZenListRow rowData) {
  final callback = rowData.enabled ? rowData.onTap : null;
  final titleWidget = rowData._titleWidget;
  final subtitleWidget = rowData._subtitleWidget;
  final leading = rowData.leading;
  final trailing = rowData.trailing;
  final row = LayoutBuilder(
    builder: (context, constraints) {
      // CupertinoListTile gives its trailing child unbounded width. On a narrow
      // row an amount can consume all the space needed by the title and icon.
      final isNarrow =
          trailing != null &&
          constraints.maxWidth < 320 * MediaQuery.textScalerOf(context).scale(1);
      return CupertinoListTile(
        leading: leading,
        title: titleWidget,
        subtitle: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?subtitleWidget,
                  if (subtitleWidget != null) const SizedBox(height: 4),
                  DefaultTextStyle(
                    style: CupertinoTheme.of(context).textTheme.textStyle,
                    child: trailing,
                  ),
                ],
              )
            : subtitleWidget,
        trailing: isNarrow
            ? null
            : trailing ?? (callback == null ? null : const CupertinoListTileChevron()),
        onTap: callback,
      );
    },
  );
  if (callback == null) {
    return rowData.enabled ? row : Semantics(enabled: false, child: row);
  }
  return FocusRing.wrapping(
    child: FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            callback();
            return null;
          },
        ),
      },
      child: Semantics(button: true, enabled: true, child: row),
    ),
  );
}

/// Builds the Material implementation for platform-independent tests.
Widget buildMaterialListRow(BuildContext context, ZenListRow rowData) {
  final callback = rowData.enabled ? rowData.onTap : null;
  final titleWidget = rowData._titleWidget;
  final subtitleWidget = rowData._subtitleWidget;

  final row = ListTile(
    leading: rowData.leading,
    title: titleWidget,
    subtitle: subtitleWidget,
    trailing: rowData.trailing ?? (callback == null ? null : const Icon(Icons.chevron_right)),
    enabled: rowData.enabled,
    onTap: callback,
  );
  return callback == null ? row : FocusRing.wrapping(child: row);
}
