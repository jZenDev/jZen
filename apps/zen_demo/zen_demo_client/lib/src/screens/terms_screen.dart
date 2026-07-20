import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_transport/zen_transport.dart';

import '../demo_messages.dart';
import '../providers.dart';

/// Loads and displays the localized Markdown terms of service, re-fetching when the language
/// changes. Ported from ../DartZen/apps/ZenDemo/dartzen_demo_client/lib/src/screens/terms_screen.dart
/// (which used flutter_markdown); jZen renders the Markdown source as selectable text to keep the
/// demo free of a discontinued dependency - the point being that localized content is fetched
/// from the real server, which this shows plainly.
class DemoTermsScreen extends ConsumerStatefulWidget {
  const DemoTermsScreen({required this.messages, super.key});

  final DemoMessages messages;

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
    final language = ref.watch(languageProvider);
    if (language != _loadedLanguage) {
      // Language changed (or first build): reload after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && language != _loadedLanguage) _load(language);
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.messages.termsTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(child: Text(widget.messages.termsError(_error!)));
    }
    if (_terms == null) {
      return Center(child: Text(widget.messages.termsLoading));
    }
    return SingleChildScrollView(
      child: SelectableText(_terms!.content),
    );
  }
}
