import 'package:flutter/widgets.dart';

/// Lays two coupled fields (a range's start and end) side by side, or one above the other when
/// there is no room: a narrow container, or text scaled to 150% or more, where two fields in a
/// row would clip their labels (WCAG 1.4.4 and 1.4.10).
class ZenPairLayout extends StatelessWidget {
  /// Lays out [first] and [second].
  const ZenPairLayout({required this.first, required this.second, super.key});

  /// The field read first: a range's start.
  final Widget first;

  /// The field read second: a range's end.
  final Widget second;

  static const double _gap = 12;
  static const double _minRowWidth = 400;

  @override
  Widget build(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stacked = constraints.maxWidth < _minRowWidth * scale.clamp(1, 3);
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              first,
              const SizedBox(height: _gap),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: first),
            const SizedBox(width: _gap),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
