import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'library_store.dart';
import 'models.dart';
import 'reader_screen.dart';
import 'state_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LotmApp());
}

class LotmApp extends StatelessWidget {
  const LotmApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LOTM Reader',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffc7a86c),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xff10171d),
    ),
    home: const LibraryHome(),
  );
}

class LibraryHome extends StatefulWidget {
  const LibraryHome({super.key});
  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> {
  LibraryStore? library;
  StateStore? reading;
  String? error;
  int tab = 0;
  bool downloadAll = false;
  static const files = MethodChannel('dev.lotm.reader/documents');

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final state = StateStore(File('${dir.path}/reading-state.json'));
      await state.load();
      final books = LibraryStore(
        Directory('${dir.path}/library'),
        parseCatalog(await rootBundle.loadString('assets/meta.json')),
      );
      await books.initialize();
      if (!mounted) {
        books.dispose();
        state.dispose();
        return;
      }
      library = books;
      reading = state;
      library!.addListener(_refresh);
      reading!.addListener(_refresh);
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _open(Edition edition, Chapter chapter) async {
    if (!library!.status(edition).complete) {
      setState(() => tab = 2);
      _notice('Download the entire edition before reading.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          library: library!,
          state: reading!,
          edition: edition,
          chapter: chapter,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _download(Edition edition) async {
    if (library!.busy) {
      _notice('Pause the current download first.');
      return;
    }
    await library!.download(edition);
  }

  Future<void> _all() async {
    if (library!.busy || downloadAll) return;
    setState(() {
      tab = 2;
      downloadAll = true;
    });
    try {
      for (final e in library!.editions) {
        if (!downloadAll) break;
        if (library!.status(e).complete) continue;
        await library!.download(e);
        if (!library!.status(e).complete) break;
      }
    } finally {
      if (mounted) setState(() => downloadAll = false);
    }
  }

  Future<void> _remove(Edition e) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove downloaded edition?'),
        content: Text(
          '${e.title}\n${e.language}\n\nYour progress, bookmarks, and notes will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) await library!.remove(e);
  }

  Future<void> _export() async {
    try {
      final result = await files.invokeMethod<bool>('export', {
        'text': jsonEncode(reading!.data),
        'name': 'lotm-reading-backup.json',
      });
      if (result == true) _notice('Reading backup saved.');
    } catch (e) {
      _notice('Unable to save backup: $e');
    }
  }

  Future<void> _import() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore reading backup?'),
        content: const Text(
          'The selected backup will replace your current progress, bookmarks, notes, and reader settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose backup'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final text = await files.invokeMethod<String>('import');
      if (text != null) {
        await reading!.import(text);
        _notice('Reading backup restored.');
      }
    } catch (e) {
      _notice('Unable to restore backup: $e');
    }
  }

  @override
  void dispose() {
    library?.dispose();
    reading?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (library == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('LOTM Reader')),
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Unable to open the library.\n$error'),
                ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(['Library', 'Bookmarks', 'Downloads', 'Settings'][tab]),
        actions: [
          if (tab == 0)
            IconButton(
              tooltip: 'Download all editions',
              onPressed: library!.busy || downloadAll ? null : _all,
              icon: const Icon(Icons.download_for_offline_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (tab) {
          0 => _library(),
          1 => _bookmarks(),
          2 => _downloads(),
          _ => _settings(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Bookmarks',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _library() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Beyond the gray fog',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Download an edition once. Read every chapter offline, with the same reader as the website.',
            ),
          ],
        ),
      ),
      for (final book in ['lotm', 'coi'])
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      book == 'lotm' ? Icons.menu_book : Icons.hourglass_bottom,
                      size: 32,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        book == 'lotm'
                            ? 'Lord of the Mysteries'
                            : 'Circle of Inevitability',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Cuttlefish That Loves Diving'),
                const SizedBox(height: 16),
                for (final e in library!.editions.where((e) => e.book == book))
                  _editionRow(e),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _editionRow(Edition e) {
    final s = library!.status(e);
    final progress = reading!.progress[e.key];
    final slug = progress is Map ? progress['slug'] as int : 1;
    final chapter = e.chapter(slug) ?? e.chapters.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.language, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            '${e.chapters.length} chapters · ${s.complete ? 'Available offline' : s.phase}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: s.complete
                    ? () => _open(e, chapter)
                    : s.active || library!.busy
                    ? null
                    : () => _download(e),
                icon: Icon(s.complete ? Icons.play_arrow : Icons.download),
                label: Text(
                  s.complete
                      ? progress == null
                            ? 'Read'
                            : 'Continue · Ch. $slug'
                      : s.done > 0
                      ? 'Resume download'
                      : 'Download edition',
                ),
              ),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ChapterList(
                      library: library!,
                      edition: e,
                      onOpen: (c) => _open(e, c),
                    ),
                  ),
                ),
                child: const Text('Chapters'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _downloads() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Downloads include every chapter and available illustration in the selected edition. Keep the app open while downloading. If Android closes it, tap Resume to continue.',
      ),
      const SizedBox(height: 12),
      if (library!.busy || downloadAll)
        OutlinedButton.icon(
          onPressed: () {
            downloadAll = false;
            library!.pause();
            _refresh();
          },
          icon: const Icon(Icons.pause),
          label: const Text('Pause download'),
        ),
      for (final e in library!.editions)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(e.language),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value:
                      library!.status(e).active &&
                          library!.status(e).phase ==
                              'Downloading illustrations'
                      ? null
                      : library!.status(e).done / e.chapters.length,
                ),
                const SizedBox(height: 8),
                Text(
                  '${library!.status(e).phase} · ${library!.status(e).done}/${e.chapters.length} chapters',
                ),
                if (library!.status(e).bytes > 0)
                  Text(
                    '${(library!.status(e).bytes / 1048576).toStringAsFixed(1)} MB stored',
                  ),
                if (library!.status(e).missingImages > 0)
                  Text(
                    '${library!.status(e).missingImages} illustration(s) are unavailable on the source website. All available content is saved.',
                  ),
                if (library!.status(e).error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      library!.status(e).error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (!library!.status(e).complete)
                      FilledButton.tonal(
                        onPressed: library!.busy || downloadAll
                            ? null
                            : () => _download(e),
                        child: Text(
                          library!.status(e).done > 0 ? 'Resume' : 'Download',
                        ),
                      ),
                    if (library!.status(e).complete)
                      TextButton(
                        onPressed: () async {
                          try {
                            _notice(
                              await library!.verify(e)
                                  ? 'All downloaded files verified.'
                                  : 'This edition needs repair. Tap Resume.',
                            );
                          } catch (e) {
                            _notice('Verification failed: $e');
                          }
                        },
                        child: const Text('Verify files'),
                      ),
                    if (library!.status(e).done > 0)
                      TextButton(
                        onPressed: library!.status(e).active
                            ? null
                            : () => _remove(e),
                        child: const Text('Remove download'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _bookmarks() {
    final entries = reading!.bookmarks.entries.toList()
      ..sort(
        (a, b) => ((b.value['updatedAt'] ?? 0) as num).compareTo(
          (a.value['updatedAt'] ?? 0) as num,
        ),
      );
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Save bookmarks and notes with the bookmark button while reading.',
          ),
        ),
      );
    }
    return ListView(
      children: [
        for (final b in entries)
          ListTile(
            leading: const Icon(Icons.bookmark),
            title: Text(b.value['title'] as String? ?? b.key),
            subtitle: Text('${b.key}\n${b.value['note']}'),
            isThreeLine: true,
            onTap: () {
              final p = b.key.split('/');
              final e = library!.editions
                  .where((e) => e.key == '${p[0]}/${p[1]}')
                  .firstOrNull;
              final c = e?.chapter(int.parse(p[2]));
              if (e != null && c != null) _open(e, c);
            },
          ),
      ],
    );
  }

  Widget _settings() => ListView(
    children: [
      const ListTile(
        leading: Icon(Icons.public),
        title: Text('Chapter source'),
        subtitle: Text(defaultSource),
      ),
      const ListTile(
        leading: Icon(Icons.palette_outlined),
        title: Text('Reader appearance'),
        subtitle: Text(
          'Open the settings button inside a chapter for the same themes, fonts, spacing, and text settings as the website.',
        ),
      ),
      ListTile(
        leading: const Icon(Icons.save_alt),
        title: const Text('Export reading backup'),
        subtitle: const Text(
          'Progress, bookmarks, notes, and appearance settings',
        ),
        onTap: _export,
      ),
      ListTile(
        leading: const Icon(Icons.restore),
        title: const Text('Restore reading backup'),
        onTap: _import,
      ),
      ListTile(
        leading: const Icon(Icons.description_outlined),
        title: const Text('License and credits'),
        onTap: () async {
          final text = await rootBundle.loadString('assets/license.md');
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('License and credits')),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText(text),
                ),
              ),
            ),
          );
        },
      ),
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('LOTM Reader · 1.0.0'),
        subtitle: Text(
          'Fan translations. Support the original author and licensed releases. Comments and account synchronization require the online website.',
        ),
      ),
    ],
  );
}

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
      appBar: AppBar(title: Text(widget.edition.language)),
      body: Column(
        children: [
          Padding(
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
