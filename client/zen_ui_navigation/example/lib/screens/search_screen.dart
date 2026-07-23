import 'package:flutter/material.dart';

import '../l10n/generated/example_localizations.dart';

/// Search screen with search functionality demo
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
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
    _filteredItems = _allItems;
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
    // Resolved in build, not cached in state: a locale switch rebuilds this subtree and the
    // new wording is picked up with no didUpdateWidget bookkeeping of its own.
    final messages = ExampleLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(messages.searchTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: messages.searchHint,
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
                          '${messages.searchSelected}${_filteredItems[index]}',
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
