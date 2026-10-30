import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../../l10n/generated/demo_localizations.dart';

enum _Plan { monthly, quarterly, yearly, lifetime }

/// Checkboxes, a radio group and filter chips: choosing without typing. Local state only.
class ShowcaseSelectionSection extends StatefulWidget {
  const ShowcaseSelectionSection({super.key});

  @override
  State<ShowcaseSelectionSection> createState() => _ShowcaseSelectionSectionState();
}

class _ShowcaseSelectionSectionState extends State<ShowcaseSelectionSection> {
  bool _email = true;
  bool _sms = false;
  bool _terms = false;
  _Plan? _plan;
  final Set<String> _tags = {'groceries'};

  /// The parent checkbox over the two channels: mixed while only one of them is on.
  bool? get _all => _email == _sms ? _email : null;

  @override
  Widget build(BuildContext context) {
    final m = DemoLocalizations.of(context);
    final heading = Theme.of(context).textTheme.titleMedium;
    final tags = {
      'groceries': m.showcaseTagGroceries,
      'travel': m.showcaseTagTravel,
      'rent': m.showcaseTagRent,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(m.showcaseSelection, style: heading),
        const SizedBox(height: 8),
        ZenCheckboxRow(
          label: m.showcaseAllChannels,
          value: _all,
          onChanged: (value) => setState(() {
            _email = value;
            _sms = value;
          }),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 24),
          child: Column(
            children: [
              ZenCheckboxRow(
                label: m.showcaseEmail,
                value: _email,
                onChanged: (value) => setState(() => _email = value),
              ),
              ZenCheckboxRow(
                label: m.showcaseSms,
                value: _sms,
                onChanged: (value) => setState(() => _sms = value),
              ),
            ],
          ),
        ),
        ZenCheckboxRow(
          label: m.showcaseTerms,
          subtitle: m.showcaseTermsHelp,
          value: _terms,
          onChanged: (value) => setState(() => _terms = value),
        ),
        ZenCheckboxRow(label: m.showcaseDisabled, value: true, onChanged: null),
        const SizedBox(height: 16),
        ZenRadioGroup<_Plan>(
          label: m.showcasePlan,
          options: [
            ZenRadioOption(value: _Plan.monthly, label: m.showcaseMonthly),
            ZenRadioOption(
              value: _Plan.quarterly,
              label: m.showcaseQuarterly,
              subtitle: m.showcaseQuarterlyHelp,
              enabled: false,
            ),
            ZenRadioOption(
              value: _Plan.yearly,
              label: m.showcaseYearly,
              subtitle: m.showcaseYearlyHelp,
            ),
            ZenRadioOption(value: _Plan.lifetime, label: m.showcaseLifetime),
          ],
          value: _plan,
          onChanged: (value) => setState(() => _plan = value),
        ),
        const SizedBox(height: 16),
        Text(m.showcaseFilters, style: heading),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final tag in tags.entries)
              ZenFilterChip(
                label: tag.value,
                selected: _tags.contains(tag.key),
                onSelected: (on) => setState(() => on ? _tags.add(tag.key) : _tags.remove(tag.key)),
              ),
            ZenFilterChip(label: m.showcaseTagArchived, selected: false, onSelected: null),
          ],
        ),
      ],
    );
  }
}
