import 'package:zen_localization/zen_localization.dart';
import 'package:flutter/material.dart';

import '../l10n/example_messages.dart';

/// Search screen with search functionality demo
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.localization,
    required this.language,
    super.key,
  });

  final ZenLocalizationService localization;
  final String language;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  late ExampleMessages _messages;
  final List<String> _allItems = [
    'Flutter',
    'Dart',
    'Navigation',
    'Riverpod',
    'Material Design',
    'Adaptive UI',
    'Cross-platform',
    'Mobile Development',
    'Web Development',
    'Desktop Development',
  ];
  List<String> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _messages = ExampleMessages(widget.localization, widget.language);
    _filteredItems = _allItems;
  }

  @override
  void didUpdateWidget(SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language ||
        oldWidget.localization != widget.localization) {
      _messages = ExampleMessages(widget.localization, widget.language);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterItems(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = _allItems;
      } else {
        _filteredItems = _allItems
            .where((item) => item.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_messages.searchTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _messages.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterItems('');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: _filterItems,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: CircleAvatar(child: Text(_filteredItems[index][0])),
                  title: Text(_filteredItems[index]),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${_messages.searchSelected}${_filteredItems[index]}',
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
