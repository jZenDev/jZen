import 'package:zen_localization/zen_localization.dart';
import 'package:flutter/material.dart';

import '../l10n/example_messages.dart';

/// Profile screen showing user information
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.localization,
    required this.language,
    super.key,
  });

  final ZenLocalizationService localization;
  final String language;

  @override
  Widget build(BuildContext context) {
    final messages = ExampleMessages(localization, language);

    return Scaffold(
      appBar: AppBar(
        title: Text(messages.profileTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(messages.profileEditClicked)),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person,
                    size: 60,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'John Doe',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'john.doe@example.com',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Card(
            child: Column(
              children: [
                _ProfileTile(
                  icon: Icons.badge,
                  title: messages.profileBadgeCount,
                  subtitle: messages.profileBadgeSubtitle,
                ),
                const Divider(height: 1),
                _ProfileTile(
                  icon: Icons.location_on,
                  title: messages.profileLocation,
                  subtitle: messages.profileLocationValue,
                ),
                const Divider(height: 1),
                _ProfileTile(
                  icon: Icons.calendar_today,
                  title: messages.profileMemberSince,
                  subtitle: messages.profileMemberSinceValue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                _ProfileActionTile(
                  icon: Icons.notifications,
                  title: messages.profileNotifications,
                  onTap: () {},
                ),
                const Divider(height: 1),
                _ProfileActionTile(
                  icon: Icons.security,
                  title: messages.profilePrivacy,
                  onTap: () {},
                ),
                const Divider(height: 1),
                _ProfileActionTile(
                  icon: Icons.help,
                  title: messages.profileHelpSupport,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
