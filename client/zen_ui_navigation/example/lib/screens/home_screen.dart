import 'package:zen_localization/zen_localization.dart';
import 'package:flutter/material.dart';

import '../l10n/example_messages.dart';

/// Home screen showing an overview
class HomeScreen extends StatelessWidget {
  const HomeScreen({
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
        title: Text(messages.homeTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.home,
              size: 120,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              messages.homeWelcome,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                messages.homeDescription,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            _buildFeatureList(context, messages),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureList(BuildContext context, ExampleMessages messages) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              messages.homeFeaturesTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _FeatureItem(text: messages.homeFeaturesAdaptive),
            _FeatureItem(text: messages.homeFeaturesHighlights),
            _FeatureItem(text: messages.homeFeaturesOverflow),
            _FeatureItem(text: messages.homeFeaturesBadges),
            _FeatureItem(text: messages.homeFeaturesRiverpod),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text),
    );
  }
}
