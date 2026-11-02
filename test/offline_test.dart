import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotm_reader/library_store.dart';
import 'package:lotm_reader/models.dart';
import 'package:lotm_reader/reader_server.dart';
import 'package:lotm_reader/state_store.dart';

class NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  NetworkTestBinding();
  late Directory temp;
  late HttpServer source;
  late Edition edition;
  late LibraryStore library;
  late Map<String, int> requests;
  var brokenImage = false;
  var brokenChapter = false;
  final original =
      '<h1 id="chapter">Chapter 1: Crimson</h1><p><em>Ouch!</em> Klein &amp; Melissa.</p><figure><img src="/assets/images/lotm/test.webp" width="10" height="20"><figcaption>Cover</figcaption></figure><p><a href="#fn1">1</a></p><aside id="fn1">Footnote</aside>';
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lotm-offline-test');
    source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = {};
    brokenImage = false;
    brokenChapter = false;
    source.listen((request) async {
      final path = request.uri.path;
      requests[path] = (requests[path] ?? 0) + 1;
      if (path.startsWith('/read/')) {
        if (brokenChapter) {
          request.response.statusCode = 503;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<html><body><article class="chapter-content prose prose-lg">$original</article></body></html>',
        );
      } else if (path.endsWith('.webp')) {
        if (brokenImage) {
          request.response.statusCode = 404;
        } else {
          request.response.add([
            ...ascii.encode('RIFF'),
            0,
            0,
            0,
            0,
            ...ascii.encode('WEBP'),
            0,
          ]);
        }
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    edition = Edition('lotm', 'webnovel', [
      for (var i = 1; i <= 3; i++)
        Chapter('lotm', 'webnovel', i, 'Chapter $i', 'Volume 1', i),
    ]);
    library = LibraryStore(Directory('${temp.path}/library'), [
      edition,
    ], source: 'http://127.0.0.1:${source.port}');
    await library.initialize();
  });
  tearDown(() async {
    library.dispose();
    await source.close(force: true);
    await temp.delete(recursive: true);
  });

  test('all books and translations read online without a download', () async {
    final editions = parseCatalog(
      await File('reader/source/lib/meta.json').readAsString(),
    );
    final onlineLibrary = LibraryStore(
      Directory('${temp.path}/online'),
      editions,
      source: library.source,
    );
    addTearDown(onlineLibrary.dispose);
    await onlineLibrary.initialize();
    expect(editions, hasLength(5));
    expect(editions.map((e) => e.book).toSet(), {'lotm', 'coi'});
    for (final e in editions) {
      // A paused bulk download must not pause online chapter or image requests.
      onlineLibrary.pause();
      for (final c in [e.chapters.first, e.chapters[1], e.chapters.last]) {
        final content = await onlineLibrary.readChapter(e, c);
        expect(content.html, original);
        expect(content.offline, false);
        expect(requests['/read/${c.key}'], 1);
      }
      expect(
        await onlineLibrary.readIllustration(
          e,
          '/assets/images/lotm/test.webp',
          online: true,
        ),
        isNotNull,
      );
      expect(onlineLibrary.status(e).complete, false);
      expect(onlineLibrary.status(e).done, 0);
      expect(await onlineLibrary.folder(e).exists(), false);
    }
  });

  test(
    'online chapter failures can be retried without download state',
    () async {
      brokenChapter = true;
      await expectLater(
        library.readChapter(edition, edition.chapters.first),
        throwsA(isA<HttpException>()),
      );
      expect(library.status(edition).error, isNull);
      brokenChapter = false;
      final content = await library.readChapter(
        edition,
        edition.chapters.first,
      );
      expect(content.html, original);
      expect(content.offline, false);
      expect(await library.folder(edition).exists(), false);
    },
  );

  test(
    'local server proxies online illustrations and keeps renderer isolated',
    () async {
      final renderer = ReaderServer(library)
        ..edition = edition
        ..online = true;
      await renderer.start();
      addTearDown(renderer.close);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final uri = renderer.uri.replace(path: '/assets/images/lotm/test.webp');
      var response = await (await client.getUrl(uri)).close();
      expect(response.statusCode, 200);
      expect(
        response.headers.value('Content-Security-Policy'),
        contains("img-src 'self' data:"),
      );
      expect(
        await response.fold<List<int>>([], (a, b) => a..addAll(b)),
        isNotEmpty,
      );
      expect(requests['/assets/images/lotm/test.webp'], 1);
      expect(await library.folder(edition).exists(), false);
      brokenImage = true;
      response = await (await client.getUrl(uri)).close();
      expect(response.statusCode, 404);
      await response.drain<void>();
      renderer.online = false;
      final count = requests['/assets/images/lotm/test.webp'];
      response = await (await client.getUrl(uri)).close();
      expect(response.statusCode, 404);
      await response.drain<void>();
      expect(requests['/assets/images/lotm/test.webp'], count);
      response = await (await client.getUrl(uri.replace(query: ''))).close();
      expect(response.statusCode, 403);
      await response.drain<void>();
    },
  );

  test(
    'downloads exact online HTML and assets; reopening and full-text search work with source offline',
    () async {
      expect(library.status(edition).complete, false);
      await library.download(edition);
      expect(library.status(edition).error, isNull);
      expect(library.status(edition).complete, true);
      for (final chapter in edition.chapters) {
        expect(
          await library.chapterFile(edition, chapter.slug).readAsString(),
          original,
        );
      }
      expect(requests['/assets/images/lotm/test.webp'], 1);
      expect(await library.verify(edition), true);
      await source.close(force: true);
      final content = await library.readChapter(
        edition,
        edition.chapters.first,
      );
      expect(content.html, original);
      expect(content.offline, true);
      expect(
        await library.readIllustration(
          edition,
          '/assets/images/lotm/test.webp',
          online: false,
        ),
        isNotNull,
      );
      final reopened = LibraryStore(library.root, [
        edition,
      ], source: library.source);
      await reopened.initialize();
      expect(reopened.status(edition).complete, true);
      expect(
        await reopened.search(edition, 'Klein', fullText: true),
        hasLength(3),
      );
      expect(
        await reopened.search(edition, 'not in book', fullText: true),
        isEmpty,
      );
      reopened.dispose();
    },
  );

  test(
    'pause does not unlock partial content and resume reuses durable chapter checkpoints',
    () async {
      var paused = false;
      library.addListener(() {
        if (!paused && library.status(edition).done >= 1) {
          paused = true;
          library.pause();
        }
      });
      await library.download(edition);
      expect(library.status(edition).complete, false);
      expect(
        await File('${library.folder(edition).path}/complete.json').exists(),
        false,
      );
      final alreadyFetched = Map<String, int>.from(requests);
      await library.download(edition);
      expect(library.status(edition).complete, true);
      for (final entry in alreadyFetched.entries) {
        expect(requests[entry.key], entry.value);
      }
    },
  );

  test(
    'source images returning 404 are recorded as unavailable; source text is preserved',
    () async {
      brokenImage = true;
      await library.download(edition);
      expect(library.status(edition).complete, true);
      expect(library.status(edition).missingImages, 1);
      expect(await library.chapterFile(edition, 1).readAsString(), original);
    },
  );

  test('damaged content is detected and repaired by resuming', () async {
    await library.download(edition);
    await library.chapterFile(edition, 2).writeAsString('damaged');
    expect(await library.verify(edition), false);
    expect(library.status(edition).complete, false);
    await library.download(edition);
    expect(library.status(edition).complete, true);
    expect(await library.verify(edition), true);
    expect(requests['/read/lotm/webnovel/2'], 2);
    expect(requests['/read/lotm/webnovel/1'], 1);
  });

  test('startup detects missing files without using the network', () async {
    await library.download(edition);
    await library.assetFile(edition, '/assets/images/lotm/test.webp').delete();
    final count = requests.values.fold(0, (a, b) => a + b);
    final reopened = LibraryStore(library.root, [
      edition,
    ], source: library.source);
    await reopened.initialize();
    expect(reopened.status(edition).complete, false);
    expect(requests.values.fold(0, (a, b) => a + b), count);
    reopened.dispose();
  });

  test('refuses error pages and unsafe asset paths', () {
    expect(
      () => LibraryStore.extractArticle('<html>Sign in</html>'),
      throwsFormatException,
    );
    expect(LibraryStore.safePath('../private/state.json'), false);
    expect(LibraryStore.safePath('assets/../../private'), false);
    expect(
      () => LibraryStore.imagePaths(
        '<img src="https://unknown.example/tracker.png">',
      ),
      throwsFormatException,
    );
  });

  test(
    'progress, bookmark notes, and settings survive serialized atomic writes and backup restore',
    () async {
      final file = File('${temp.path}/state.json');
      final state = StateStore(file);
      state.bookmarks['lotm/webnovel/2'] = {
        'note': 'Remember this clue',
        'title': 'Situation',
      };
      state.settings['fontSize'] = 28;
      await Future.wait([
        state.saveProgress('lotm/webnovel', 1, .1),
        state.saveProgress('lotm/webnovel', 2, .7),
      ]);
      final backup = await file.readAsString();
      final reopened = StateStore(file);
      await reopened.load();
      expect(reopened.progress['lotm/webnovel']['slug'], 2);
      expect(reopened.progress['lotm/webnovel']['scrollRatio'], .7);
      expect(
        reopened.bookmarks['lotm/webnovel/2']['note'],
        'Remember this clue',
      );
      expect(reopened.settings['fontSize'], 28);
      final restored = StateStore(File('${temp.path}/restored.json'));
      await restored.import(backup);
      expect(restored.data, reopened.data);
      await expectLater(
        restored.import('{"version":2}'),
        throwsFormatException,
      );
      expect(restored.data, reopened.data);
      state.dispose();
      reopened.dispose();
      restored.dispose();
    },
  );
}
