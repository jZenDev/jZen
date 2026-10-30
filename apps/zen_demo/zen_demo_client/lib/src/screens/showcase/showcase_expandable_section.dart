import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../../l10n/generated/demo_localizations.dart';

/// An expandable section with real content, one that keeps what is typed while closed, and a
/// disabled one.
class ShowcaseExpandableSection extends StatefulWidget {
  const ShowcaseExpandableSection({super.key});

  @override
  State<ShowcaseExpandableSection> createState() => _ShowcaseExpandableSectionState();
}

class _ShowcaseExpandableSectionState extends State<ShowcaseExpandableSection> {
  bool _advanced = false;
  bool _reference = false;
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = DemoLocalizations.of(context);
    final heading = Theme.of(context).textTheme.titleMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(m.showcaseExpandable, style: heading),
        const SizedBox(height: 8),
        ZenExpandableSection(
          title: m.showcaseAdvanced,
          subtitle: m.showcaseAdvancedHelp,
          expanded: _advanced,
          onChanged: (value) => setState(() => _advanced = value),
          child: Padding(padding: const EdgeInsets.all(16), child: Text(m.showcaseAdvancedBody)),
        ),
        // maintainState: the half-typed code survives closing and reopening the section.
        ZenExpandableSection(
          title: m.showcaseReference,
          expanded: _reference,
          maintainState: true,
          onChanged: (value) => setState(() => _reference = value),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ZenTextField(label: m.showcaseReference, controller: _code),
          ),
        ),
        ZenExpandableSection(
          title: m.showcaseLocked,
          expanded: false,
          onChanged: null,
          child: Text(m.showcaseAdvancedBody),
        ),
      ],
    );
  }
}
