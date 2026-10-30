import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/demo_localizations.dart';
import 'showcase/showcase_expandable_section.dart';
import 'showcase/showcase_menu_section.dart';
import 'showcase/showcase_search_section.dart';
import 'showcase/showcase_selection_section.dart';
import 'showcase/showcase_sliders_section.dart';

/// Interactive examples of shared controls, with local state only.
class ShowcaseScreen extends StatefulWidget {
  const ShowcaseScreen({super.key});

  @override
  State<ShowcaseScreen> createState() => _ShowcaseScreenState();
}

class _ShowcaseScreenState extends State<ShowcaseScreen> {
  bool _notifications = false;
  int _choice = 0;
  int? _selection = 0;
  DateTime? _date;
  DateTime? _from;
  DateTime? _to;
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _minimum = TextEditingController();
  final _maximum = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = DemoLocalizations.of(context);
    final heading = Theme.of(context).textTheme.titleMedium;
    void message() => showZenMessage(context, m.showcaseMessage);
    return ZenPageScaffold(
      title: m.navShowcase,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(m.showcaseIntro),
          const SizedBox(height: 16),
          ZenSwitchRow(
            label: m.showcaseSwitch,
            subtitle: m.showcaseSwitchHelp,
            value: _notifications,
            onChanged: (value) => setState(() => _notifications = value),
          ),
          ZenSwitchRow(label: m.showcaseDisabled, value: false, onChanged: null),
          const Divider(height: 32),
          Text(m.showcaseButtons, style: heading),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ZenButton(label: m.showcaseShowMessage, onPressed: message),
              ZenButton(
                label: m.showcaseDisabled,
                onPressed: null,
                variant: ZenButtonVariant.secondary,
              ),
              ZenIconButton(
                icon: Icons.info_outline,
                label: m.showcaseShowMessage,
                onPressed: message,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ZenListItemActions(
            showActionsLabel: m.showItemActions,
            hideActionsLabel: m.hideItemActions,
            actions: [
              ZenListItemAction(
                icon: Icons.info_outline,
                label: m.showcaseShowMessage,
                onPressed: message,
              ),
            ],
            child: ZenListRow(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: m.showcaseRow,
              subtitle: m.showcaseRowHelp,
              trailing: ZenIconButton(
                icon: Icons.info_outline,
                label: m.showcaseShowMessage,
                onPressed: message,
              ),
              onTap: message,
            ),
          ),
          const Divider(height: 32),
          Text(m.showcaseChoose, style: heading),
          const SizedBox(height: 8),
          ZenSegmentedControl<int>(
            segments: [
              ZenSegment(value: 0, label: m.showcaseFirst),
              ZenSegment(value: 1, label: m.showcaseSecond),
            ],
            selected: _choice,
            onChanged: (value) => setState(() => _choice = value),
          ),
          const SizedBox(height: 16),
          ZenSelect<int>(
            label: m.showcaseChoose,
            items: const [0, 1],
            itemLabel: (value) => value == 0 ? m.showcaseFirst : m.showcaseSecond,
            value: _selection,
            onChanged: (value) => setState(() => _selection = value),
          ),
          const Divider(height: 32),
          const ShowcaseSelectionSection(),
          const Divider(height: 32),
          const ShowcaseSlidersSection(),
          const Divider(height: 32),
          const ShowcaseSearchSection(),
          const Divider(height: 32),
          const ShowcaseMenuSection(),
          const Divider(height: 32),
          const ShowcaseExpandableSection(),
          const Divider(height: 32),
          Text(m.showcaseFields, style: heading),
          const SizedBox(height: 8),
          ZenTextField(label: m.showcaseName, controller: _name),
          const SizedBox(height: 16),
          ZenAmountField(label: m.showcaseAmount, controller: _amount, maxFractionDigits: 2),
          const SizedBox(height: 16),
          ZenAmountRangeField(
            minLabel: m.showcaseMinimum,
            maxLabel: m.showcaseMaximum,
            minController: _minimum,
            maxController: _maximum,
            maxFractionDigits: 2,
          ),
          const SizedBox(height: 16),
          ZenDateField(
            label: m.showcaseDate,
            value: _date,
            clearable: true,
            onChanged: (value) => setState(() => _date = value),
          ),
          const SizedBox(height: 16),
          ZenDateRangeField(
            fromLabel: m.showcaseFrom,
            toLabel: m.showcaseTo,
            from: _from,
            to: _to,
            onChanged: (from, to) => setState(() {
              _from = from;
              _to = to;
            }),
          ),
          const Divider(height: 32),
          Text(m.showcaseProgress, style: heading),
          const SizedBox(height: 8),
          ZenProgressBar(label: m.showcaseProgress, value: 0.65),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft, child: ZenProgressIndicator(size: 24)),
        ],
      ),
    );
  }
}
