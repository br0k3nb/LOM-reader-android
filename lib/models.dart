import 'dart:convert';

class Chapter {
  const Chapter(
    this.book,
    this.tl,
    this.slug,
    this.title,
    this.category,
    this.index,
  );
  final String book, tl, title, category;
  final int slug, index;
  String get key => '$book/$tl/$slug';
  Map<String, dynamic> toJson() => {
    'book': book,
    'tl': tl,
    'slug': slug,
    'title': title,
    'category': category,
    'idx': index,
  };
}

class Edition {
  const Edition(this.book, this.tl, this.chapters);
  final String book, tl;
  final List<Chapter> chapters;
  String get key => '$book/$tl';
  String get title =>
      book == 'lotm' ? 'Lord of the Mysteries' : 'Circle of Inevitability';
  String get language => switch (tl) {
    'pt-br' => 'Português (Brasil)',
    'oldtl' => 'English · Original translation',
    _ => 'English · Webnovel',
  };
  Chapter? chapter(int slug) {
    for (final c in chapters) {
      if (c.slug == slug) return c;
    }
    return null;
  }
}

List<Edition> parseCatalog(String text) {
  final data = jsonDecode(text) as Map<String, dynamic>;
  return [
    for (final book in data.entries)
      for (final tl in (book.value as Map<String, dynamic>).entries)
        Edition(book.key, tl.key, [
          for (final raw in tl.value as List)
            Chapter(
              book.key,
              tl.key,
              (raw['slug'] as num).toInt(),
              raw['title'] as String,
              raw['category'] as String,
              (raw['index'] as num).toInt(),
            ),
        ]),
  ];
}

class DownloadStatus {
  int done = 0;
  int total = 0;
  int bytes = 0;
  int missingImages = 0;
  bool complete = false;
  bool active = false;
  String? error;
  String phase = 'Not downloaded';
}
