import 'package:material_ui/material_ui.dart';

class FeatureItem extends StatelessWidget {
  const FeatureItem({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(text));
  }
}
