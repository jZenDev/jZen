import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

import 'focus_ring.dart';

/// A navigable list row with a platform-appropriate interaction.
class ZenListRow extends StatelessWidget {
  const ZenListRow({required this.title, required this.onTap, this.subtitle, super.key});

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FocusRing.wrapping(
    child: buildZenListRow(context, title, subtitle, onTap, apple: zenIsApplePlatform),
  );
}

/// Builds either platform idiom so both can be exercised in tests.
Widget buildZenListRow(
  BuildContext context,
  String title,
  String? subtitle,
  VoidCallback? onTap, {
  required bool apple,
}) {
  if (apple) {
    // InkWell supplies keyboard activation; its Apple configuration suppresses Material ink.
    return Theme(
      data: Theme.of(
        context,
      ).copyWith(splashFactory: NoSplash.splashFactory, highlightColor: Colors.transparent),
      child: ListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(CupertinoIcons.chevron_right),
        onTap: onTap,
        splashColor: Colors.transparent,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        tileColor: Colors.transparent,
      ),
    );
  }
  return ListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
