import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../../l10n/generated/demo_localizations.dart';

/// A continuous slider, a stepped one and a range slider, each with a disabled example. The units
/// are the app's: the controls only write the numbers the formatters hand them.
class ShowcaseSlidersSection extends StatefulWidget {
  const ShowcaseSlidersSection({super.key});

  @override
  State<ShowcaseSlidersSection> createState() => _ShowcaseSlidersSectionState();
}

class _ShowcaseSlidersSectionState extends State<ShowcaseSlidersSection> {
  double _volume = 40;
  double _rating = 3;
  RangeValues _price = const RangeValues(100, 300);

  @override
  Widget build(BuildContext context) {
    final m = DemoLocalizations.of(context);
    final heading = Theme.of(context).textTheme.titleMedium;
    String euros(double v) => m.showcaseEuros(v.round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(m.showcaseSliders, style: heading),
        const SizedBox(height: 8),
        ZenSlider(
          label: m.showcaseVolume,
          value: _volume,
          min: 0,
          max: 100,
          valueFormatter: (v) => m.showcaseDecibels(v.round()),
          onChanged: (value) => setState(() => _volume = value),
        ),
        ZenSlider(
          label: m.showcaseRating,
          value: _rating,
          min: 1,
          max: 5,
          divisions: 4,
          valueFormatter: (v) => m.showcaseRatingValue(v.round()),
          onChanged: (value) => setState(() => _rating = value),
        ),
        ZenSlider(
          label: m.showcaseDisabled,
          value: 60,
          min: 0,
          max: 100,
          valueFormatter: (v) => m.showcaseDecibels(v.round()),
          onChanged: null,
        ),
        const SizedBox(height: 8),
        ZenRangeSlider(
          label: m.showcasePrice,
          startLabel: m.showcasePriceMin,
          endLabel: m.showcasePriceMax,
          values: _price,
          min: 0,
          max: 500,
          divisions: 50,
          valueFormatter: euros,
          onChanged: (range) => setState(() => _price = range),
        ),
        ZenRangeSlider(
          label: m.showcaseDisabled,
          startLabel: m.showcasePriceMin,
          endLabel: m.showcasePriceMax,
          values: const RangeValues(150, 350),
          min: 0,
          max: 500,
          valueFormatter: euros,
          onChanged: null,
        ),
      ],
    );
  }
}
