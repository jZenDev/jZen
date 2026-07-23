import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';

import '../l10n/generated/example_localizations.dart';
import '../providers/localization_providers.dart';

/// Settings screen with app preferences
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  double _textScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final messages = ExampleLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(messages.settingsTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          _SectionHeader(title: messages.settingsAppearanceTitle),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: Text(messages.settingsAppearanceDarkMode),
            subtitle: Text(messages.settingsAppearanceDarkModeSubtitle),
            value: _darkModeEnabled,
            onChanged: (value) {
              setState(() {
                _darkModeEnabled = value;
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: Text(messages.settingsAppearanceTextSize),
            subtitle: Slider(
              value: _textScale,
              min: 0.8,
              max: 1.5,
              divisions: 7,
              label: '${(_textScale * 100).round()}%',
              onChanged: (value) {
                setState(() {
                  _textScale = value;
                });
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(messages.languageLabel),
            trailing: SegmentedButton<Locale>(
              segments: [
                for (final tag in ZenLocales.supported)
                  ButtonSegment<Locale>(
                    value: Locale(tag),
                    label: Text(tag.toUpperCase()),
                  ),
              ],
              selected: {ref.watch(localeProvider)},
              onSelectionChanged: (selection) =>
                  ref.read(localeProvider.notifier).setLocale(selection.first),
            ),
          ),
          const Divider(),
          _SectionHeader(title: messages.settingsNotificationsTitle),
          SwitchListTile(
            secondary: const Icon(Icons.notifications),
            title: Text(messages.settingsNotificationsPush),
            subtitle: Text(messages.settingsNotificationsReceive),
            value: _notificationsEnabled,
            onChanged: (value) {
              setState(() {
                _notificationsEnabled = value;
              });
            },
          ),
          const Divider(),
          _SectionHeader(title: messages.settingsNavigationTitle),
          ListTile(
            leading: const Icon(Icons.navigation),
            title: Text(messages.settingsNavigationType),
            subtitle: Text(messages.settingsNavigationAdaptive),
            trailing: const Icon(Icons.check),
          ),
          const Divider(),
          _SectionHeader(title: messages.settingsAboutTitle),
          ListTile(
            leading: const Icon(Icons.info),
            title: Text(messages.settingsAboutVersion),
            subtitle: const Text('1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(messages.settingsAboutPackage),
            subtitle: Text(messages.settingsAboutPackageValue),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
