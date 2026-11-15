import 'package:flutter/material.dart';

/// A plain explanatory line in the settings list.
class SettingsLine extends StatelessWidget {
  final String text;

  const SettingsLine(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text(text));
}
