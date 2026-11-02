import 'package:flutter/material.dart';
import 'library_store.dart';
import 'models.dart';
import 'design.dart';

class ChapterList extends StatefulWidget {
  const ChapterList({
    super.key,
    required this.library,
    required this.edition,
    required this.onOpen,
  });
  final LibraryStore library;
  final Edition edition;
  final Future<void> Function(Chapter) onOpen;
  @override
  State<ChapterList> createState() => _ChapterListState();
}

class _ChapterListState extends State<ChapterList> {
  String query = '';
  String? category;
  bool fullText = false;
  bool searching = false;
  int searchGeneration = 0;
  late List<Chapter> matches;
  @override
  void initState() {
    super.initState();
    matches = widget.edition.chapters;
  }

  Future<void> _search() async {
    final generation = ++searchGeneration;
    setState(() => searching = true);
    try {
      final result = await widget.library.search(
        widget.edition,
        query,
        fullText: fullText,
      );
      if (mounted && generation == searchGeneration) {
        setState(() {
          matches = result;
          searching = false;
        });
      }
    } catch (e) {
      if (mounted && generation == searchGeneration) {
        setState(() => searching = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = category == null
        ? matches
        : matches.where((c) => c.category == category).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.edition.language,
          style: const TextStyle(fontSize: 17),
        ),
      ),
      body: Column(
        children: [
          MotionEntry(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Chapter number, title, or phrase',
                  border: OutlineInputBorder(),
                ),
                onChanged: (text) {
                  query = text;
                  if (!fullText) _search();
                },
                onSubmitted: (_) => _search(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: category ?? '',
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All volumes'),
                      ),
                      for (final c
                          in widget.edition.chapters
                              .map((c) => c.category)
                              .toSet())
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (value) =>
                        setState(() => category = value == '' ? null : value),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Full text'),
                  tooltip: widget.library.status(widget.edition).complete
                      ? 'Search downloaded chapter text'
                      : 'Download this edition to search its full text',
                  selected: fullText,
                  onSelected: widget.library.status(widget.edition).complete
                      ? (value) {
                          setState(() => fullText = value);
                          _search();
                        }
                      : null,
                ),
              ],
            ),
          ),
          if (fullText)
            TextButton.icon(
              onPressed: _search,
              icon: const Icon(Icons.search),
              label: const Text('Search downloaded text'),
            ),
          if (searching) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('${shown.length} chapters'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final c = shown[index];
                return ListTile(
                  leading: SizedBox(
                    width: 48,
                    child: Text('${c.slug}', textAlign: TextAlign.center),
                  ),
                  title: Text(c.title),
                  subtitle: Text(c.category),
                  onTap: () => widget.onOpen(c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
