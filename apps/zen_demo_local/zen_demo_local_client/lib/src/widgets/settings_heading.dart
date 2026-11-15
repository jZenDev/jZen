import 'package:material_ui/material_ui.dart';

/// A section title in the settings list, read as a heading.
class SettingsHeading extends StatelessWidget {
  final String text;

  const SettingsHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}
