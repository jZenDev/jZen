import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../../l10n/generated/demo_localizations.dart';

/// A search field filtering a small local list, with the empty-result state the app owns.
class ShowcaseSearchSection extends StatefulWidget {
  const ShowcaseSearchSection({super.key});

  @override
  State<ShowcaseSearchSection> createState() => _ShowcaseSearchSectionState();
}

class _ShowcaseSearchSectionState extends State<ShowcaseSearchSection> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = DemoLocalizations.of(context);
    final heading = Theme.of(context).textTheme.titleMedium;
    final accounts = [
      m.showcaseAccountSavings,
      m.showcaseAccountChecking,
      m.showcaseAccountTravel,
      m.showcaseAccountEmergency,
      m.showcaseAccountRetirement,
    ];
    final needle = _query.trim().toLowerCase();
    final matches = [
      for (final name in accounts)
        if (name.toLowerCase().contains(needle)) name,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(m.showcaseSearch, style: heading),
        const SizedBox(height: 8),
        // The controller is this screen's: the field reads and clears it and never disposes it.
        ZenSearchField(
          label: m.showcaseSearchLabel,
          hint: m.showcaseSearchHint,
          controller: _controller,
          onChanged: (query) => setState(() => _query = query),
        ),
        const SizedBox(height: 8),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(m.showcaseNoResults(_query.trim())),
          )
        else
          for (final name in matches)
            ZenListRow(leading: const Icon(Icons.account_balance_wallet_outlined), title: name),
      ],
    );
  }
}
