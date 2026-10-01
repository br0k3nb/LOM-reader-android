import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'models.dart';

const defaultSource = 'https://lotmreader.vercel.app';

class DownloadPaused implements Exception {}

/// Content is persistent app data, never an evictable browser cache.
class LibraryStore extends ChangeNotifier {
  LibraryStore(
    this.root,
    this.editions, {
    this.source = defaultSource,
    HttpClient? client,
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
  }
  final Directory root;
  final List<Edition> editions;
  final String source;
  final HttpClient _client;
  final Map<String, DownloadStatus> statuses = {};
  bool _paused = false;
  bool get busy => statuses.values.any((s) => s.active);
  DownloadStatus status(Edition e) =>
      statuses.putIfAbsent(e.key, DownloadStatus.new);
  Directory folder(Edition e) => Directory('${root.path}/${e.book}/${e.tl}');
  File chapterFile(Edition e, int slug) =>
      File('${folder(e).path}/chapters/$slug.html');
  File assetFile(Edition e, String path) => File('${folder(e).path}$path');

  Future<void> initialize() async {
    await root.create(recursive: true);
    for (final e in editions) {
      final s = status(e)..total = e.chapters.length;
      final ready = File('${folder(e).path}/complete.json');
      if (await ready.exists()) {
        try {
          final info =
              jsonDecode(await ready.readAsString()) as Map<String, dynamic>;
          if (info['source'] != source ||
              info['edition'] != e.key ||
              info['chapters'] != e.chapters.length) {
            throw const FormatException('Edition changed');
          }
          final entries = (info['files'] as Map<String, dynamic>).entries;
          for (final file in entries) {
            if (!safePath(file.key)) throw const FormatException('Unsafe file');
            final local = File('${folder(e).path}/${file.key}');
            if (!await local.exists() ||
                await local.length() != file.value['bytes']) {
              throw const FormatException('Incomplete download');
            }
          }
          for (final chapter in e.chapters) {
            if (!(info['files'] as Map).containsKey(
              'chapters/${chapter.slug}.html',
            )) {
              throw const FormatException('Missing chapter');
            }
          }
          s.complete = true;
          s.done = s.total;
          s.bytes = (info['bytes'] as num).toInt();
          s.missingImages = (info['unavailable'] as List).length;
          s.phase = 'Available offline';
        } catch (_) {
          s.error =
              'Some local files are missing. Resume the download to repair this edition.';
          await ready.delete();
        }
      }
      if (!s.complete) {
        s.done = 0;
        for (final c in e.chapters) {
          if (await chapterFile(e, c.slug).exists()) s.done++;
        }
        if (s.done > 0) s.phase = 'Paused · tap Resume';
      }
    }
    notifyListeners();
  }

  static bool safePath(String path) =>
      path.isNotEmpty &&
      !path.startsWith('/') &&
      !path.contains('\\') &&
      !path.split('/').any((s) => s == '..' || s == '.' || s.isEmpty) &&
      !path.contains('\u0000');

  static String extractArticle(String page) {
    final match = RegExp(
      r'<article\b[^>]*class=["\x27][^"\x27]*chapter-content[^>]*>([\s\S]*?)</article>',
      caseSensitive: false,
    ).firstMatch(page);
    if (match == null || match.group(1)!.trim().isEmpty) {
      throw const FormatException(
        'The website returned no chapter. Check the source URL and try again.',
      );
    }
    return match.group(1)!;
  }

  static Set<String> imagePaths(String html) {
    final paths = <String>{};
    for (final m in RegExp(
      r'<img\b[^>]*\bsrc=["\x27]([^"\x27]+)',
      caseSensitive: false,
    ).allMatches(html)) {
      final path = Uri.decodeComponent(m.group(1)!.replaceAll('&amp;', '&'));
      if (!path.startsWith('/assets/images/') || !safePath(path.substring(1))) {
        throw FormatException('Unsupported illustration URL: $path');
      }
      paths.add(path);
    }
    return paths;
  }

  Future<List<int>?> _fetch(
    String path, {
    bool allowMissing = false,
    int limit = 5 * 1024 * 1024,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_paused) throw DownloadPaused();
      try {
        final request = await _client
            .getUrl(Uri.parse(source).resolve(path))
            .timeout(const Duration(seconds: 30));
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'LOTMReader/1.0 (offline download)',
        );
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode == 404 && allowMissing) {
          await response.drain<void>();
          return null;
        }
        if (response.statusCode != 200) {
          await response.drain<void>();
          throw HttpException('HTTP ${response.statusCode} for $path');
        }
        final bytes = <int>[];
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          if (_paused) throw DownloadPaused();
          bytes.addAll(chunk);
          if (bytes.length > limit) {
            throw const FormatException(
              'Download exceeds the allowed file size.',
            );
          }
        }
        if (bytes.isEmpty) {
          throw const FormatException('The server returned an empty file.');
        }
        return bytes;
      } on DownloadPaused {
        rethrow;
      } catch (_) {
        if (attempt == 2) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }
    throw StateError('Download failed');
  }

  Future<void> _atomicWrite(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.part');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  void pause() {
    _paused = true;
  }

  Future<void> download(Edition e) async {
    if (busy) throw StateError('Another edition is downloading.');
    if (status(e).complete) return;
    _paused = false;
    final s = status(e)
      ..active = true
      ..error = null
      ..phase = 'Downloading chapters';
    notifyListeners();
    try {
      // Each successful chapter is its own durable checkpoint. Four workers bound load and memory.
      final queue = e.chapters.iterator;
      final images = <String>{};
      final files = <String, dynamic>{};
      var totalBytes = 0;
      var done = 0;
      Future<void> worker() async {
        while (!_paused && queue.moveNext()) {
          final c = queue.current;
          final file = chapterFile(e, c.slug);
          String html;
          if (await file.exists()) {
            html = await file.readAsString();
            if (html.trim().isEmpty) {
              await file.delete();
              throw const FormatException(
                'Empty local chapter. Resume to repair.',
              );
            }
          } else {
            final bytes = (await _fetch('/read/${c.key}'))!;
            html = extractArticle(utf8.decode(bytes));
            await _atomicWrite(file, utf8.encode(html));
          }
          images.addAll(imagePaths(html));
          final bytes = utf8.encode(html);
          files['chapters/${c.slug}.html'] = {
            'bytes': bytes.length,
            'sha256': sha256.convert(bytes).toString(),
          };
          totalBytes += bytes.length;
          s.done = ++done;
          notifyListeners();
        }
      }

      // Do not mark anything ready until all workers have finished, including on failure.
      await Future.wait(List.generate(4, (_) => worker()), eagerError: false);
      if (_paused) throw DownloadPaused();
      s.phase = 'Downloading illustrations';
      final unavailable = <String>[];
      for (final path in images.toList()..sort()) {
        if (_paused) throw DownloadPaused();
        final file = assetFile(e, path);
        if (!await file.exists()) {
          final bytes = await _fetch(
            path,
            allowMissing: true,
            limit: 30 * 1024 * 1024,
          );
          if (bytes == null) {
            unavailable.add(path);
            continue;
          }
          await _atomicWrite(file, bytes);
        }
        final bytes = await file.readAsBytes();
        // Reject login/error pages masquerading as successful images.
        final webp =
            bytes.length > 12 &&
            ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
        final png = bytes.length > 8 && bytes[0] == 137 && bytes[1] == 80;
        final jpg = bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216;
        if (!webp && !png && !jpg) {
          await file.delete();
          throw FormatException(
            'Invalid illustration returned by the server: $path',
          );
        }
        files[path.substring(1)] = {
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        };
        totalBytes += bytes.length;
        s.bytes = totalBytes;
        notifyListeners();
      }
      if (_paused) throw DownloadPaused();
      await _atomicWrite(
        File('${folder(e).path}/complete.json'),
        utf8.encode(
          jsonEncode({
            'version': 1,
            'source': source,
            'edition': e.key,
            'chapters': e.chapters.length,
            'bytes': totalBytes,
            'files': files,
            'unavailable': unavailable,
            'downloadedAt': DateTime.now().toIso8601String(),
          }),
        ),
      );
      s.complete = true;
      s.bytes = totalBytes;
      s.missingImages = unavailable.length;
      s.phase = 'Available offline';
    } on DownloadPaused {
      s.phase = 'Paused · tap Resume';
    } catch (error) {
      s.phase = 'Download interrupted';
      s.error = '$error';
    } finally {
      s.active = false;
      notifyListeners();
    }
  }

  Future<void> remove(Edition e) async {
    if (status(e).active) {
      throw StateError('Pause this download before removing it.');
    }
    final dir = folder(e);
    if (await dir.exists()) await dir.delete(recursive: true);
    statuses[e.key] = DownloadStatus()..total = e.chapters.length;
    notifyListeners();
  }

  Future<bool> verify(Edition e) async {
    final manifest = File('${folder(e).path}/complete.json');
    if (!await manifest.exists()) return false;
    final info =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    for (final entry in (info['files'] as Map<String, dynamic>).entries) {
      if (!safePath(entry.key)) return false;
      final file = File('${folder(e).path}/${entry.key}');
      if (!await file.exists() ||
          sha256.convert(await file.readAsBytes()).toString() !=
              entry.value['sha256']) {
        if (await file.exists()) await file.delete();
        await manifest.delete();
        status(e).complete = false;
        status(e).error =
            'A damaged file was found. Resume the download to repair it.';
        notifyListeners();
        return false;
      }
    }
    return true;
  }

  Future<List<Chapter>> search(
    Edition e,
    String query, {
    bool fullText = false,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return e.chapters;
    if (!fullText) {
      return e.chapters
          .where((c) => '${c.slug} ${c.title}'.toLowerCase().contains(q))
          .toList();
    }
    if (!status(e).complete) {
      throw StateError('Download this edition before searching its text.');
    }
    return compute(_searchFiles, {
      'path': folder(e).path,
      'query': q,
      'chapters': e.chapters,
    });
  }

  @override
  void dispose() {
    _paused = true;
    _client.close(force: true);
    super.dispose();
  }
}

List<Chapter> _searchFiles(Map<String, dynamic> input) {
  final chapters = input['chapters'] as List<Chapter>;
  final q = input['query'] as String;
  final tag = RegExp(r'<[^>]+>');
  return chapters.where((c) {
    final html = File(
      '${input['path']}/chapters/${c.slug}.html',
    ).readAsStringSync();
    return '${c.title} ${html.replaceAll(tag, ' ').replaceAll(RegExp(r'\s+'), ' ')}'
        .toLowerCase()
        .contains(q);
  }).toList();
}
