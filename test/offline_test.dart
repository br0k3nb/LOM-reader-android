import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotm_reader/library_store.dart';
import 'package:lotm_reader/models.dart';
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
  final original =
      '<h1 id="chapter">Chapter 1: Crimson</h1><p><em>Ouch!</em> Klein &amp; Melissa.</p><figure><img src="/assets/images/lotm/test.webp" width="10" height="20"><figcaption>Cover</figcaption></figure><p><a href="#fn1">1</a></p><aside id="fn1">Footnote</aside>';
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lotm-offline-test');
    source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = {};
    brokenImage = false;
    source.listen((request) async {
      final path = request.uri.path;
      requests[path] = (requests[path] ?? 0) + 1;
      if (path.startsWith('/read/')) {
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
