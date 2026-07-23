import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_transport/zen_transport.dart';

import '../l10n/generated/demo_localizations.dart';
import '../providers.dart';

/// Loads and displays the localized Markdown terms of service, re-fetching when the language
/// changes. The Markdown source is rendered as selectable text rather than through a Markdown
/// widget, to keep the demo free of a discontinued dependency - the point being that localized
/// content is fetched from the real server, which this shows plainly.
class DemoTermsScreen extends ConsumerStatefulWidget {
  const DemoTermsScreen({super.key});

  @override
  ConsumerState<DemoTermsScreen> createState() => _DemoTermsScreenState();
}

class _DemoTermsScreenState extends ConsumerState<DemoTermsScreen> {
  Terms? _terms;
  String? _error;
  String? _loadedLanguage;

  Future<void> _load(String language) async {
    setState(() {
      _terms = null;
      _error = null;
      _loadedLanguage = language;
    });
    final result = await ref.read(demoRepositoryProvider).terms(language: language);
    if (!mounted) return;
    result.fold(
      (terms) => setState(() => _terms = terms),
      (failure) => setState(() => _error = failure.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = DemoLocalizations.of(context);
    // The language code, not the Locale: it is what the server's Accept-Language and the
    // /demo/terms query expect (ADR-007).
    final language = ref.watch(localeProvider).languageCode;
    if (language != _loadedLanguage) {
      // Language changed (or first build): reload after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && language != _loadedLanguage) _load(language);
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(messages.termsTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildBody(messages),
      ),
    );
  }

  Widget _buildBody(DemoLocalizations messages) {
    if (_error != null) {
      return Center(child: Text(messages.termsError(_error!)));
    }
    if (_terms == null) {
      return Center(child: Text(messages.termsLoading));
    }
    return SingleChildScrollView(
      child: SelectableText(_terms!.content),
    );
  }
}
